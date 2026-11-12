import Foundation

/// Mentions handed to Plico as JSON files in a folder, instead of through
/// Microsoft Graph: written by an agent reading Outlook on the web, or by a
/// flow (Power Automate) saving them to a synced folder. Plico reads each
/// file, keeps its messages like synced ones and deletes the file.
///
/// A file holds one run (`{"checkedAt": …, "messages": [ … ]}`), a list of
/// messages or one message. A message needs a subject and a date, and is read
/// loosely so Graph-style names work too:
/// `id`, `subject`, `from` (`{"name", "address"}`, Graph's
/// `{"emailAddress": {…}}` or a plain address), `receivedAt` /
/// `receivedDateTime` (ISO 8601), `preview` / `bodyPreview`, `webLink` /
/// `webUrl`, `internetMessageId`.
public enum MentionsFolder {
    /// Messages from the folder are kept under this account.
    public static let accountID = "outlook-web"

    /// `~/Library/Application Support/SmartNotes/Mentions Inbox`.
    public static func defaultURL() throws -> URL {
        try PersistenceController.defaultStoreURL().deletingLastPathComponent()
            .appendingPathComponent("Mentions Inbox", isDirectory: true)
    }

    public struct Batch: Equatable, Sendable {
        public var drafts: [ExternalItemDraft]
        /// When the source looked (the run's `checkedAt`), if it said.
        public var checkedAt: Date?
    }

    /// Nil when the data isn't JSON of a known shape.
    public static func batch(from data: Data) -> Batch? {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
        if let run = json as? [String: Any], let messages = run["messages"] as? [[String: Any]] {
            return Batch(drafts: messages.compactMap(draft), checkedAt: (run["checkedAt"] as? String).flatMap(date))
        }
        if let messages = json as? [[String: Any]] { return Batch(drafts: messages.compactMap(draft), checkedAt: nil) }
        if let message = json as? [String: Any], let draft = draft(from: message) { return Batch(drafts: [draft], checkedAt: nil) }
        return nil
    }

    static func draft(from message: [String: Any]) -> ExternalItemDraft? {
        func string(_ keys: String...) -> String? {
            for key in keys {
                if let value = message[key] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return value.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            return nil
        }
        guard let subject = string("subject", "Subject"),
              let receivedAt = string("receivedAt", "receivedDateTime", "DateTimeReceived").flatMap(date) else { return nil }
        let (senderName, senderAddress) = sender(message["from"] ?? message["From"] ?? message["sender"])
        let internetMessageId = string("internetMessageId", "InternetMessageId")
        // Same message, same card: the source's ID, else what identifies it.
        let externalId = string("id", "Id") ?? internetMessageId
            ?? [senderAddress ?? senderName ?? "", subject, ISO8601DateFormatter().string(from: receivedAt)].joined(separator: "|")
        let webUrl = string("webLink", "webUrl", "WebLink").flatMap(URL.init(string:))
            .flatMap { $0.scheme?.lowercased() == "https" && LinkValidator.isAllowed($0) ? $0 : nil }
        return ExternalItemDraft(
            key: ExternalItemKey(provider: .outlook, accountId: accountID, externalId: externalId),
            internetMessageId: internetMessageId, subject: subject, senderName: senderName, senderAddress: senderAddress,
            preview: String((string("preview", "bodyPreview", "BodyPreview") ?? "").prefix(1000)),
            receivedAt: receivedAt, webUrl: webUrl, importRule: OutlookImportScope.mentions.rawValue
        )
    }

    private static func sender(_ value: Any?) -> (String?, String?) {
        if let address = value as? String {
            return address.contains("@") ? (nil, address) : (address, nil)
        }
        guard var fields = value as? [String: Any] else { return (nil, nil) }
        if let inner = fields["emailAddress"] as? [String: Any] { fields = inner }
        let name = (fields["name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let address = (fields["address"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return (name, address)
    }

    private static func date(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }

    /// Reads every `.json` file in `folder` into `repository` and deletes it.
    /// A file that can't be read is left as it is, for a look later.
    /// Returns the latest `checkedAt` (or now) when anything was read.
    @MainActor
    public static func importFiles(in folder: URL, into repository: ExternalItemRepository, now: Date) -> Date? {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        var checkedAt: Date?
        for file in files.filter({ $0.pathExtension.lowercased() == "json" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard let data = try? Data(contentsOf: file), let batch = batch(from: data) else {
                Log.app.error("Mentions folder: skipped a file that isn't a mentions file")
                continue
            }
            do {
                try repository.upsert(batch.drafts, syncedAt: now)
                try? FileManager.default.removeItem(at: file)
                checkedAt = max(checkedAt ?? .distantPast, batch.checkedAt ?? now)
            } catch {
                Log.app.error("Mentions folder: saving failed: \(String(describing: error), privacy: .public)")
            }
        }
        return checkedAt
    }
}

/// Calls `onChange` (on the main queue) when files are added to a folder.
final class FolderWatcher: @unchecked Sendable {
    private let source: DispatchSourceFileSystemObject

    init?(folder: URL, onChange: @escaping @MainActor () -> Void) {
        let descriptor = open(folder.path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename], queue: .main)
        source.setEventHandler { MainActor.assumeIsolated { onChange() } }
        source.setCancelHandler { close(descriptor) }
        source.resume()
    }

    deinit { source.cancel() }
}

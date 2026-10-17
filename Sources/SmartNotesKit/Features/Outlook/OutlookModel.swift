import Foundation
import Observation

/// State of the Outlook connection as shown in Mentions.
public enum OutlookStatus: Equatable, Sendable {
    /// No app registration yet (Settings ▸ Outlook).
    case notConfigured
    case disconnected
    case connecting
    case syncing
    case ready
    /// Network unavailable: cached messages are shown.
    case offline
    /// The session expired or access was revoked: reconnect.
    case needsReconnect(String)
    case failed(String)
}

/// Outlook connection, sync and the Mentions list. Read-only towards Outlook:
/// nothing is ever sent, deleted, moved or marked read there.
@MainActor
@Observable
public final class OutlookModel {
    public private(set) var status: OutlookStatus = .notConfigured
    public private(set) var account: OutlookAccount?
    public private(set) var items: [ExternalItem] = []
    public private(set) var lastSyncAt: Date?
    public var selectedItemID: UUID?
    /// Sample messages while Outlook isn't set up (never stored).
    public private(set) var isShowingSamples = false

    public var configuration: OutlookConfiguration {
        didSet {
            guard configuration != oldValue else { return }
            preferences.saveConfiguration(configuration)
            if account == nil { status = configuration.isComplete ? .disconnected : .notConfigured }
        }
    }

    public var scope: OutlookImportScope {
        didSet {
            guard scope != oldValue else { return }
            preferences.saveScope(scope)
            if isShowingSamples { items = Self.sampleItems(scope: scope) } else { reloadItems() }
            Task { await refresh() }
        }
    }

    public var selectedItem: ExternalItem? {
        selectedItemID.flatMap { id in items.first { $0.id == id } }
    }

    @ObservationIgnored private let repository: ExternalItemRepository
    @ObservationIgnored private let integrationStates: IntegrationStateRepository
    @ObservationIgnored private let session: OutlookSession
    @ObservationIgnored private let preferences: OutlookPreferences
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var syncTask: Task<Void, Never>?

    public init(repository: ExternalItemRepository, integrationStates: IntegrationStateRepository,
                session: OutlookSession, preferences: OutlookPreferences, now: @escaping () -> Date = Date.init) {
        self.repository = repository
        self.integrationStates = integrationStates
        self.session = session
        self.preferences = preferences
        self.now = now
        self.configuration = preferences.configuration()
        self.scope = preferences.scope()
        self.account = preferences.account()
        if let account {
            status = .ready
            lastSyncAt = (try? integrationStates.state(provider: .outlook, accountId: account.id))?.lastSyncAt
            reloadItems()
        } else {
            status = configuration.isComplete ? .disconnected : .notConfigured
        }
    }

    // MARK: Connection

    public func connect() async {
        status = .connecting
        do {
            let account = try await session.signIn(configuration: configuration)
            self.account = account
            preferences.saveAccount(account)
            isShowingSamples = false
            status = .ready
            await refresh()
        } catch OutlookAuthError.cancelled {
            status = account == nil ? .disconnected : .ready
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    /// Clears the tokens; optionally also the messages saved on this Mac. Notes are never touched.
    public func disconnect(removeSavedMessages: Bool) {
        if let account {
            try? session.signOut(account: account)
            try? integrationStates.remove(provider: .outlook, accountId: account.id)
            if removeSavedMessages { _ = try? repository.removeAll(provider: .outlook, accountId: account.id) }
        }
        account = nil
        preferences.saveAccount(nil)
        items = []
        selectedItemID = nil
        lastSyncAt = nil
        status = configuration.isComplete ? .disconnected : .notConfigured
    }

    // MARK: Sync

    /// Refreshes if the last sync is older than `minimumInterval` (launch, app activation).
    public func refreshIfStale(minimumInterval: TimeInterval = 120) {
        guard account != nil, status != .syncing else { return }
        if let lastSyncAt, now().timeIntervalSince(lastSyncAt) < minimumInterval { return }
        syncTask = Task { await refresh() }
    }

    public func refresh() async {
        guard let account, status != .syncing else { return }
        status = .syncing
        let scope = self.scope
        do {
            let client = session.client(account: account, configuration: configuration)
            let (messages, complete) = try await client.messages(scope: scope)
            let drafts = messages.compactMap { $0.draft(accountID: account.id, scope: scope) }
            let syncedAt = now()
            try repository.upsert(drafts, syncedAt: syncedAt)
            if complete {
                // Messages that no longer match (unflagged, deleted, moved) leave the list.
                let current = Set(drafts.map(\.key.externalId))
                let stale = try repository.items(provider: .outlook, accountId: account.id, includeDismissed: true)
                    .filter { $0.importRule == scope.rawValue && !current.contains($0.externalId) }
                try repository.remove(keys: stale.map(\.dedupeKey))
            }
            try integrationStates.save(IntegrationState(provider: .outlook, accountId: account.id, lastSyncAt: syncedAt, syncStatus: .idle))
            lastSyncAt = syncedAt
            status = .ready
        } catch GraphError.offline {
            status = .offline
        } catch GraphError.unauthorized, OutlookAuthError.noRefreshToken {
            status = .needsReconnect("Your Outlook session expired.")
        } catch OutlookAuthError.tokenRequestFailed(let message) {
            status = .needsReconnect(message)
        } catch let error as GraphError {
            status = .failed(error.localizedDescription)
            if case .forbidden = error { status = .needsReconnect(error.localizedDescription) }
        } catch {
            status = .failed(error.localizedDescription)
        }
        reloadItems()
    }

    // MARK: Items

    /// Hides the card in Smart Notes only; the email in Outlook is untouched.
    public func dismiss(_ id: UUID) {
        if isShowingSamples {
            items.removeAll { $0.id == id }
        } else {
            try? repository.setDismissed(id: id, true)
            reloadItems()
        }
        if selectedItemID == id { selectedItemID = nil }
    }

    public func select(_ id: UUID?) {
        selectedItemID = id
        if let id, !isShowingSamples { try? repository.setSeen(id: id, true) }
    }

    /// A note with the subject, sender, a link back to Outlook and the preview.
    public func makeNote(from item: ExternalItem, rank: String) -> Note {
        let sender = [item.senderName, item.senderAddress.map { "<\($0)>" }].compactMap { $0 }.joined(separator: " ")
        let date = item.receivedAt.formatted(date: .abbreviated, time: .shortened)
        var specs: [(BlockType, RichText)] = [(.paragraph, RichText(plain: "From \(sender.isEmpty ? "unknown sender" : sender) · \(date)"))]
        if let url = item.webUrl {
            specs.append((.paragraph, RichText(runs: [TextRun("Open in Outlook", link: url)])))
        }
        if !item.preview.isEmpty {
            specs.append((.quote, RichText(plain: item.preview)))
        }
        specs.append((.paragraph, .empty))
        let ranks = Rank.evenlySpaced(specs.count)
        return Note(
            title: item.subject,
            createdAt: now(),
            manualRank: rank,
            sourceExternalItemId: isShowingSamples ? nil : item.id,
            blocks: zip(specs, ranks).map { NoteBlock(type: $0.0, rank: $1, content: $0.1) }
        )
    }

    // MARK: Samples

    public func showSamples(_ show: Bool) {
        isShowingSamples = show
        items = show ? Self.sampleItems(scope: scope) : []
        selectedItemID = nil
    }

    private func reloadItems() {
        guard let account, !isShowingSamples else { return }
        items = ((try? repository.items(provider: .outlook, accountId: account.id, includeDismissed: false)) ?? [])
            .filter { $0.importRule == scope.rawValue }
        if let selectedItemID, !items.contains(where: { $0.id == selectedItemID }) { self.selectedItemID = nil }
    }

    static func sampleItems(scope: OutlookImportScope, now: Date = .now) -> [ExternalItem] {
        let samples: [(String, String, String, TimeInterval)] = [
            ("Ada Lovelace", "Q4 roadmap review", "@you could you confirm the timeline for the reporting feature before Friday?", -1_800),
            ("Grace Hopper", "Customer escalation: export timeouts", "Looping you in (@you): the export job times out above 10k rows. Any ideas?", -14_400),
            ("Linus Pauling", "Design crit notes", "Thanks all. @you, your comments on the onboarding flow are in the doc.", -90_000),
        ]
        return samples.enumerated().map { index, sample in
            ExternalItem(provider: .outlook, accountId: "sample", externalId: "sample-\(index)",
                         subject: sample.1, senderName: sample.0, senderAddress: sample.0.lowercased().replacingOccurrences(of: " ", with: ".") + "@example.com",
                         preview: sample.2, receivedAt: now.addingTimeInterval(sample.3),
                         webUrl: URL(string: "https://outlook.office.com/mail/"), importRule: scope.rawValue, lastSyncedAt: now)
        }
    }
}

/// Non-secret Outlook preferences in UserDefaults (configuration, scope, account).
public final class OutlookPreferences: @unchecked Sendable {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func configuration() -> OutlookConfiguration { decode("SmartNotes.Outlook.Configuration") ?? OutlookConfiguration() }
    func saveConfiguration(_ value: OutlookConfiguration) { encode(value, "SmartNotes.Outlook.Configuration") }
    /// Default: mentions of you (your request).
    func scope() -> OutlookImportScope { defaults.string(forKey: "SmartNotes.Outlook.Scope").flatMap(OutlookImportScope.init(rawValue:)) ?? .mentions }
    func saveScope(_ value: OutlookImportScope) { defaults.set(value.rawValue, forKey: "SmartNotes.Outlook.Scope") }
    func account() -> OutlookAccount? { decode("SmartNotes.Outlook.Account") }
    func saveAccount(_ value: OutlookAccount?) {
        if let value { encode(value, "SmartNotes.Outlook.Account") } else { defaults.removeObject(forKey: "SmartNotes.Outlook.Account") }
    }

    private func decode<T: Decodable>(_ key: String) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    private func encode<T: Encodable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }
}

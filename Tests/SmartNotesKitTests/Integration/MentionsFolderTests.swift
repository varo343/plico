import Foundation
import Testing
@testable import SmartNotesKit

@MainActor
@Suite(.serialized) struct MentionsFolderTests {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("PlicoMentions-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func model(folder: URL) throws -> (OutlookModel, AppDependencies) {
        let deps = try AppDependencies.inMemory()
        let preferences = OutlookPreferences(defaults: UserDefaults(suiteName: "SNMentionsFolder.\(UUID().uuidString)")!)
        let model = OutlookModel(repository: deps.externalItems, integrationStates: deps.integrationStates,
                                 session: OutlookSession(tokenStore: InMemoryTokenStore()), preferences: preferences, mentionsFolder: folder)
        return (model, deps)
    }

    private let run = #"""
    {"source": "outlook-web", "checkedAt": "2026-11-06T09:30:00Z", "messages": [
      {"id": "conv-1", "subject": "Q4 review", "from": {"name": "Ada Lovelace", "address": "ada@contoso.com"},
       "receivedAt": "2026-11-06T08:00:00Z", "preview": "@Alberto can you check?", "webLink": "https://outlook.office.com/mail/id/conv-1"},
      {"subject": "Export timeouts", "from": "grace@contoso.com", "receivedAt": "2026-11-05T17:45:10.250Z"},
      {"subject": "No date"}
    ]}
    """#

    @Test func aRunFileBecomesMentions() throws {
        let batch = try #require(MentionsFolder.batch(from: Data(run.utf8)))
        #expect(batch.drafts.map(\.subject) == ["Q4 review", "Export timeouts"]) // no date: skipped
        #expect(batch.drafts[0].senderName == "Ada Lovelace" && batch.drafts[0].senderAddress == "ada@contoso.com")
        #expect(batch.drafts[0].webUrl == URL(string: "https://outlook.office.com/mail/id/conv-1"))
        #expect(batch.drafts[1].senderAddress == "grace@contoso.com" && batch.drafts[1].key.externalId.contains("Export timeouts"))
        #expect(batch.drafts.allSatisfy { $0.importRule == "mentions" && $0.key.accountId == MentionsFolder.accountID })
        #expect(batch.checkedAt == ISO8601DateFormatter().date(from: "2026-11-06T09:30:00Z"))
    }

    @Test func graphStyleMessagesAndUnsafeLinks() throws {
        let graph = #"{"id": "g1", "subject": "Hi", "from": {"emailAddress": {"name": "Ada", "address": "ada@contoso.com"}}, "receivedDateTime": "2026-11-06T08:00:00Z", "bodyPreview": "text", "webLink": "javascript:alert(1)"}"#
        let draft = try #require(MentionsFolder.batch(from: Data(graph.utf8))?.drafts.first)
        #expect(draft.senderName == "Ada" && draft.preview == "text" && draft.webUrl == nil)
        #expect(MentionsFolder.batch(from: Data("not json".utf8)) == nil)
    }

    @Test func filesAreImportedOnceDeletedAndShownWithoutAnAccount() async throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (model, _) = try model(folder: folder)
        #expect(!model.showsFolderMentions && model.items.isEmpty)

        try Data(run.utf8).write(to: folder.appendingPathComponent("run-1.json"))
        try Data("{broken".utf8).write(to: folder.appendingPathComponent("broken.json"))
        model.importMentionsFolder()
        #expect(model.showsFolderMentions)
        #expect(model.items.map(\.subject) == ["Q4 review", "Export timeouts"]) // newest first
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("run-1.json").path))
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("broken.json").path)) // left for a look

        // The same mentions again: no duplicates, and a dismissed one stays dismissed.
        model.dismiss(model.items[0].id)
        try Data(run.utf8).write(to: folder.appendingPathComponent("run-2.json"))
        model.importMentionsFolder()
        #expect(model.items.map(\.subject) == ["Export timeouts"])
    }

    @Test func aFileAddedLaterIsPickedUpByItself() async throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (model, _) = try model(folder: folder)
        try Data(run.utf8).write(to: folder.appendingPathComponent("run.json"), options: .atomic)
        for _ in 0..<300 where model.items.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        #expect(model.items.count == 2)
    }
}

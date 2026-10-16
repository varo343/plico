import Foundation
import Testing
@testable import SmartNotesKit

@MainActor
@Suite struct ExternalItemRepositoryTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let account = "user@example.com"

    private func draft(_ id: String, subject: String = "Subject", receivedOffset: TimeInterval = 0) -> ExternalItemDraft {
        ExternalItemDraft(
            key: ExternalItemKey(provider: .outlook, accountId: account, externalId: id),
            subject: subject, senderName: "Ada", senderAddress: "ada@example.com",
            preview: "Preview of \(id)", receivedAt: now.addingTimeInterval(receivedOffset),
            webUrl: URL(string: "https://outlook.office.com/mail/id/\(id)"), importRule: "flagged"
        )
    }

    @Test func secondFetchDoesNotDuplicate() throws {
        let repo = try AppDependencies.inMemory().externalItems
        let first = try repo.upsert([draft("m1"), draft("m2", receivedOffset: 10)], syncedAt: now)
        #expect(first == UpsertSummary(inserted: 2, updated: 0))

        let second = try repo.upsert([draft("m1", subject: "Edited"), draft("m2"), draft("m3")], syncedAt: now)
        #expect(second == UpsertSummary(inserted: 1, updated: 2))

        let items = try repo.items(provider: .outlook, accountId: account, includeDismissed: true)
        #expect(items.count == 3)
        #expect(items.first { $0.externalId == "m1" }?.subject == "Edited")
    }

    @Test func duplicateKeysWithinOnePageCollapse() throws {
        let repo = try AppDependencies.inMemory().externalItems
        let summary = try repo.upsert([draft("m1"), draft("m1", subject: "Later")], syncedAt: now)
        #expect(summary.inserted == 1)
        let items = try repo.items(provider: .outlook, accountId: account, includeDismissed: true)
        #expect(items.map(\.subject) == ["Later"])
    }

    @Test func localStateSurvivesResync() throws {
        let repo = try AppDependencies.inMemory().externalItems
        try repo.upsert([draft("m1"), draft("m2")], syncedAt: now)
        let m1 = try #require(try repo.items(provider: .outlook, accountId: account, includeDismissed: true).first { $0.externalId == "m1" })
        try repo.setDismissed(id: m1.id, true)
        try repo.setSeen(id: m1.id, true)

        try repo.upsert([draft("m1", subject: "Changed remotely")], syncedAt: now.addingTimeInterval(60))
        let after = try #require(try repo.item(id: m1.id))
        #expect(after.isDismissedLocally && after.isSeenLocally)
        #expect(after.subject == "Changed remotely")
        #expect(try repo.items(provider: .outlook, accountId: account, includeDismissed: false).map(\.externalId) == ["m2"])
    }

    @Test func itemsAreNewestFirstAndScopedToAccount() throws {
        let repo = try AppDependencies.inMemory().externalItems
        var other = draft("x")
        other.key.accountId = "someone-else"
        try repo.upsert([draft("old", receivedOffset: -100), draft("new", receivedOffset: 100), other], syncedAt: now)
        #expect(try repo.items(provider: .outlook, accountId: account, includeDismissed: true).map(\.externalId) == ["new", "old"])
    }

    @Test func removeAllClearsOnlyThatAccountAndNeverNotes() throws {
        let deps = try AppDependencies.inMemory(seedSampleData: true, now: now)
        var other = draft("x")
        other.key.accountId = "someone-else"
        try deps.externalItems.upsert([draft("m1"), draft("m2"), other], syncedAt: now)

        #expect(try deps.externalItems.removeAll(provider: .outlook, accountId: account) == 2)
        #expect(try deps.externalItems.items(provider: .outlook, accountId: "someone-else", includeDismissed: true).count == 1)
        #expect(try deps.notes.summaries(in: .active).count == SampleData.notes(now: now).count)
    }

    @Test func removeByKeyHandlesDeletedMessages() throws {
        let repo = try AppDependencies.inMemory().externalItems
        try repo.upsert([draft("m1"), draft("m2")], syncedAt: now)
        try repo.remove(keys: [draft("m1").key, draft("never-existed").key])
        #expect(try repo.items(provider: .outlook, accountId: account, includeDismissed: true).map(\.externalId) == ["m2"])
    }

    @Test func integrationStateRoundTrip() throws {
        let repo = try AppDependencies.inMemory().integrationStates
        #expect(try repo.state(provider: .outlook, accountId: account) == nil)
        let state = IntegrationState(provider: .outlook, accountId: account, lastSyncAt: now,
                                     deltaLink: "https://graph.microsoft.com/delta?token=abc",
                                     syncStatus: .error, lastError: "Network unavailable")
        try repo.save(state)
        #expect(try repo.state(provider: .outlook, accountId: account) == state)
        try repo.remove(provider: .outlook, accountId: account)
        #expect(try repo.state(provider: .outlook, accountId: account) == nil)
    }
}

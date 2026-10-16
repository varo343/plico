import Foundation
import SwiftData

@MainActor
public final class SwiftDataExternalItemRepository: ExternalItemRepository {
    // Holding the container keeps the store alive for as long as the repository;
    // a ModelContext alone does not retain it.
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    public init(container: ModelContainer) {
        self.container = container
    }

    public func items(provider: ExternalProvider, accountId: String, includeDismissed: Bool) throws -> [ExternalItem] {
        let providerRaw = provider.rawValue
        let predicate: Predicate<ExternalItemRecord> = includeDismissed
            ? #Predicate { $0.providerRaw == providerRaw && $0.accountId == accountId }
            : #Predicate { $0.providerRaw == providerRaw && $0.accountId == accountId && !$0.isDismissedLocally }
        let descriptor = FetchDescriptor(predicate: predicate, sortBy: [SortDescriptor(\.receivedAt, order: .reverse)])
        return try context.fetch(descriptor).compactMap(Self.item)
    }

    public func item(id: UUID) throws -> ExternalItem? {
        var descriptor = FetchDescriptor<ExternalItemRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first.flatMap(Self.item)
    }

    @discardableResult
    public func upsert(_ drafts: [ExternalItemDraft], syncedAt: Date) throws -> UpsertSummary {
        var summary = UpsertSummary(inserted: 0, updated: 0)
        // Last draft wins if a page contains the same key twice.
        var seen: [String: ExternalItemRecord] = [:]
        for draft in drafts {
            let key = draft.key.storageKey
            let record: ExternalItemRecord
            if let pending = seen[key] {
                record = pending
            } else if let existing = try existingRecord(dedupeKey: key) {
                record = existing
                summary.updated += 1
            } else {
                record = ExternalItemRecord(
                    id: UUID(), dedupeKey: key, providerRaw: draft.key.provider.rawValue,
                    accountId: draft.key.accountId, externalId: draft.key.externalId,
                    internetMessageId: nil, subject: "", senderName: nil, senderAddress: nil,
                    preview: "", receivedAt: draft.receivedAt, webUrlString: nil,
                    isDismissedLocally: false, isSeenLocally: false, importRule: "",
                    lastSyncedAt: syncedAt
                )
                context.insert(record)
                summary.inserted += 1
            }
            seen[key] = record
            record.internetMessageId = draft.internetMessageId
            record.subject = draft.subject
            record.senderName = draft.senderName
            record.senderAddress = draft.senderAddress
            record.preview = draft.preview
            record.receivedAt = draft.receivedAt
            record.webUrlString = draft.webUrl?.absoluteString
            record.importRule = draft.importRule
            record.lastSyncedAt = syncedAt
        }
        try context.save()
        return summary
    }

    public func remove(keys: [ExternalItemKey]) throws {
        for key in keys {
            if let record = try existingRecord(dedupeKey: key.storageKey) {
                context.delete(record)
            }
        }
        try context.save()
    }

    public func setDismissed(id: UUID, _ dismissed: Bool) throws {
        try update(id: id) { $0.isDismissedLocally = dismissed }
    }

    public func setSeen(id: UUID, _ seen: Bool) throws {
        try update(id: id) { $0.isSeenLocally = seen }
    }

    @discardableResult
    public func removeAll(provider: ExternalProvider, accountId: String) throws -> Int {
        let providerRaw = provider.rawValue
        let records = try context.fetch(FetchDescriptor<ExternalItemRecord>(
            predicate: #Predicate { $0.providerRaw == providerRaw && $0.accountId == accountId }
        ))
        records.forEach(context.delete)
        try context.save()
        return records.count
    }

    // MARK: - Private

    private func existingRecord(dedupeKey: String) throws -> ExternalItemRecord? {
        var descriptor = FetchDescriptor<ExternalItemRecord>(predicate: #Predicate { $0.dedupeKey == dedupeKey })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func update(id: UUID, _ change: (ExternalItemRecord) -> Void) throws {
        var descriptor = FetchDescriptor<ExternalItemRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let record = try context.fetch(descriptor).first else { return }
        change(record)
        try context.save()
    }

    private static func item(_ r: ExternalItemRecord) -> ExternalItem? {
        guard let provider = ExternalProvider(rawValue: r.providerRaw) else { return nil }
        return ExternalItem(
            id: r.id, provider: provider, accountId: r.accountId, externalId: r.externalId,
            internetMessageId: r.internetMessageId, subject: r.subject, senderName: r.senderName,
            senderAddress: r.senderAddress, preview: r.preview, receivedAt: r.receivedAt,
            webUrl: r.webUrlString.flatMap(URL.init(string:)),
            isDismissedLocally: r.isDismissedLocally, isSeenLocally: r.isSeenLocally,
            importRule: r.importRule, lastSyncedAt: r.lastSyncedAt
        )
    }
}

@MainActor
public final class SwiftDataIntegrationStateRepository: IntegrationStateRepository {
    // Holding the container keeps the store alive for as long as the repository;
    // a ModelContext alone does not retain it.
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    public init(container: ModelContainer) {
        self.container = container
    }

    public func state(provider: ExternalProvider, accountId: String) throws -> IntegrationState? {
        guard let r = try record(key: Self.key(provider, accountId)) else { return nil }
        return IntegrationState(
            provider: provider, accountId: r.accountId, lastSyncAt: r.lastSyncAt,
            deltaLink: r.deltaLink, syncStatus: SyncStatus(rawValue: r.syncStatusRaw) ?? .idle,
            lastError: r.lastError
        )
    }

    public func save(_ state: IntegrationState) throws {
        let key = Self.key(state.provider, state.accountId)
        let record: IntegrationStateRecord
        if let existing = try self.record(key: key) {
            record = existing
        } else {
            record = IntegrationStateRecord(
                key: key, providerRaw: state.provider.rawValue, accountId: state.accountId,
                lastSyncAt: nil, deltaLink: nil, syncStatusRaw: SyncStatus.idle.rawValue, lastError: nil
            )
            context.insert(record)
        }
        record.lastSyncAt = state.lastSyncAt
        record.deltaLink = state.deltaLink
        record.syncStatusRaw = state.syncStatus.rawValue
        record.lastError = state.lastError
        try context.save()
    }

    public func remove(provider: ExternalProvider, accountId: String) throws {
        guard let record = try record(key: Self.key(provider, accountId)) else { return }
        context.delete(record)
        try context.save()
    }

    private func record(key: String) throws -> IntegrationStateRecord? {
        var descriptor = FetchDescriptor<IntegrationStateRecord>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private static func key(_ provider: ExternalProvider, _ accountId: String) -> String {
        "\(provider.rawValue)|\(accountId)"
    }
}

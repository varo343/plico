import Foundation
import SwiftData

/// Persisted schema, version 1.
///
/// Records are kept separate from the domain value types so the on-disk shape
/// can evolve through `SmartNotesMigrationPlan` without touching views.
/// Enums are stored as raw strings and dates-only as ISO `YYYY-MM-DD` strings.
public enum SmartNotesSchemaV1: VersionedSchema {
    public static let versionIdentifier = Schema.Version(1, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [NoteRecord.self, BlockRecord.self, ExternalItemRecord.self, IntegrationStateRecord.self]
    }

    @Model
    public final class NoteRecord {
        @Attribute(.unique) public var id: UUID
        public var title: String
        public var createdAt: Date
        public var updatedAt: Date
        public var isPinned: Bool
        public var deletedAt: Date?
        public var priorityRaw: String
        public var plannedDay: String?
        public var dueDay: String?
        public var manualRank: String
        public var sourceExternalItemId: UUID?
        /// Folded title + body text, rebuilt on every save.
        public var searchText: String
        /// Single-line body preview, rebuilt on every save.
        public var previewText: String
        /// Title or first-line fallback, rebuilt on every save.
        public var displayTitle: String
        @Relationship(deleteRule: .cascade, inverse: \BlockRecord.note)
        public var blocks: [BlockRecord] = []

        public init(
            id: UUID, title: String, createdAt: Date, updatedAt: Date, isPinned: Bool,
            deletedAt: Date?, priorityRaw: String, plannedDay: String?, dueDay: String?,
            manualRank: String, sourceExternalItemId: UUID?, searchText: String, previewText: String,
            displayTitle: String
        ) {
            self.id = id
            self.title = title
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.isPinned = isPinned
            self.deletedAt = deletedAt
            self.priorityRaw = priorityRaw
            self.plannedDay = plannedDay
            self.dueDay = dueDay
            self.manualRank = manualRank
            self.sourceExternalItemId = sourceExternalItemId
            self.searchText = searchText
            self.previewText = previewText
            self.displayTitle = displayTitle
        }
    }

    @Model
    public final class BlockRecord {
        @Attribute(.unique) public var id: UUID
        public var typeRaw: String
        public var rank: String
        /// `RichText` JSON payload (versioned).
        public var contentData: Data
        public var isChecked: Bool
        public var indentLevel: Int
        public var note: NoteRecord?

        public init(id: UUID, typeRaw: String, rank: String, contentData: Data, isChecked: Bool, indentLevel: Int) {
            self.id = id
            self.typeRaw = typeRaw
            self.rank = rank
            self.contentData = contentData
            self.isChecked = isChecked
            self.indentLevel = indentLevel
        }
    }

    @Model
    public final class ExternalItemRecord {
        @Attribute(.unique) public var id: UUID
        /// `ExternalItemKey.storageKey`; enforces dedupe at the store level too.
        @Attribute(.unique) public var dedupeKey: String
        public var providerRaw: String
        public var accountId: String
        public var externalId: String
        public var internetMessageId: String?
        public var subject: String
        public var senderName: String?
        public var senderAddress: String?
        public var preview: String
        public var receivedAt: Date
        public var webUrlString: String?
        public var isDismissedLocally: Bool
        public var isSeenLocally: Bool
        public var importRule: String
        public var lastSyncedAt: Date

        public init(
            id: UUID, dedupeKey: String, providerRaw: String, accountId: String, externalId: String,
            internetMessageId: String?, subject: String, senderName: String?, senderAddress: String?,
            preview: String, receivedAt: Date, webUrlString: String?, isDismissedLocally: Bool,
            isSeenLocally: Bool, importRule: String, lastSyncedAt: Date
        ) {
            self.id = id
            self.dedupeKey = dedupeKey
            self.providerRaw = providerRaw
            self.accountId = accountId
            self.externalId = externalId
            self.internetMessageId = internetMessageId
            self.subject = subject
            self.senderName = senderName
            self.senderAddress = senderAddress
            self.preview = preview
            self.receivedAt = receivedAt
            self.webUrlString = webUrlString
            self.isDismissedLocally = isDismissedLocally
            self.isSeenLocally = isSeenLocally
            self.importRule = importRule
            self.lastSyncedAt = lastSyncedAt
        }
    }

    @Model
    public final class IntegrationStateRecord {
        /// "provider|accountId"
        @Attribute(.unique) public var key: String
        public var providerRaw: String
        public var accountId: String
        public var lastSyncAt: Date?
        public var deltaLink: String?
        public var syncStatusRaw: String
        public var lastError: String?

        public init(
            key: String, providerRaw: String, accountId: String, lastSyncAt: Date?,
            deltaLink: String?, syncStatusRaw: String, lastError: String?
        ) {
            self.key = key
            self.providerRaw = providerRaw
            self.accountId = accountId
            self.lastSyncAt = lastSyncAt
            self.deltaLink = deltaLink
            self.syncStatusRaw = syncStatusRaw
            self.lastError = lastError
        }
    }
}

/// Migration plan. Add `SmartNotesSchemaV2` + a stage here when the schema changes,
/// together with a migration test using a V1 fixture store.
public enum SmartNotesMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [SmartNotesSchemaV1.self] }
    public static var stages: [MigrationStage] { [] }
}

// Current-version aliases used by repositories.
public typealias NoteRecord = SmartNotesSchemaV1.NoteRecord
public typealias BlockRecord = SmartNotesSchemaV1.BlockRecord
public typealias ExternalItemRecord = SmartNotesSchemaV1.ExternalItemRecord
public typealias IntegrationStateRecord = SmartNotesSchemaV1.IntegrationStateRecord

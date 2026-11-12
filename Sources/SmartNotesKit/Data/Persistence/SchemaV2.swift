import Foundation
import SwiftData

/// Persisted schema, version 2: adds `BlockRecord.tagRaw` (block tags). Frozen:
/// existing stores are migrated from it (see `SmartNotesMigrationPlan`), so never
/// edit these models.
///
/// Only the note and block models changed; the Outlook models are shared with V1.
public enum SmartNotesSchemaV2: VersionedSchema {
    public static let versionIdentifier = Schema.Version(2, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [NoteRecord.self, BlockRecord.self, ExternalItemRecord.self, IntegrationStateRecord.self]
    }

    public typealias ExternalItemRecord = SmartNotesSchemaV1.ExternalItemRecord
    public typealias IntegrationStateRecord = SmartNotesSchemaV1.IntegrationStateRecord

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
        /// `BlockTag.storageValue`; nil when the block has no tag.
        public var tagRaw: String?
        public var note: NoteRecord?

        public init(id: UUID, typeRaw: String, rank: String, contentData: Data, isChecked: Bool, indentLevel: Int, tagRaw: String? = nil) {
            self.id = id
            self.typeRaw = typeRaw
            self.rank = rank
            self.contentData = contentData
            self.isChecked = isChecked
            self.indentLevel = indentLevel
            self.tagRaw = tagRaw
        }
    }
}

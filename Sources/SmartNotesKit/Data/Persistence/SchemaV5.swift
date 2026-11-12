import Foundation
import SwiftData

/// Persisted schema, version 5: adds `BlockRecord.imageWidth` (a picture's
/// chosen size).
///
/// Only the block model changed; the Outlook models are shared with V1.
public enum SmartNotesSchemaV5: VersionedSchema {
    public static let versionIdentifier = Schema.Version(5, 0, 0)

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
        /// Nested text as a `RichText` JSON payload; nil when the block has none.
        public var detailData: Data?
        /// The block's column; nil is the left one (0).
        public var columnIndex: Int?
        /// An image block's picture, kept beside the store rather than in it.
        @Attribute(.externalStorage) public var imageData: Data?
        /// `NoteImage.id`: lets saving skip unchanged pictures without reading them.
        public var imageID: UUID?
        /// The width an image block is shown at, in points; nil is its own size.
        public var imageWidth: Double?
        public var note: NoteRecord?

        public init(
            id: UUID, typeRaw: String, rank: String, contentData: Data, isChecked: Bool, indentLevel: Int,
            tagRaw: String? = nil, detailData: Data? = nil, columnIndex: Int? = nil, imageData: Data? = nil, imageID: UUID? = nil,
            imageWidth: Double? = nil
        ) {
            self.id = id
            self.typeRaw = typeRaw
            self.rank = rank
            self.contentData = contentData
            self.isChecked = isChecked
            self.indentLevel = indentLevel
            self.tagRaw = tagRaw
            self.detailData = detailData
            self.columnIndex = columnIndex
            self.imageData = imageData
            self.imageID = imageID
            self.imageWidth = imageWidth
        }
    }
}

/// Migration plan. Add a new schema version + a stage here when the schema changes,
/// together with a migration test using a fixture store of the previous version.
public enum SmartNotesMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [SmartNotesSchemaV1.self, SmartNotesSchemaV2.self, SmartNotesSchemaV3.self, SmartNotesSchemaV4.self, SmartNotesSchemaV5.self]
    }
    public static var stages: [MigrationStage] {
        // Each version only adds optional columns, so existing blocks simply
        // have no tag (V2), no nested text (V3), sit in the left column with no picture (V4),
        // and pictures show at their own size (V5).
        [
            .lightweight(fromVersion: SmartNotesSchemaV1.self, toVersion: SmartNotesSchemaV2.self),
            .lightweight(fromVersion: SmartNotesSchemaV2.self, toVersion: SmartNotesSchemaV3.self),
            .lightweight(fromVersion: SmartNotesSchemaV3.self, toVersion: SmartNotesSchemaV4.self),
            .lightweight(fromVersion: SmartNotesSchemaV4.self, toVersion: SmartNotesSchemaV5.self),
        ]
    }
}

// Current-version aliases used by repositories.
public typealias NoteRecord = SmartNotesSchemaV5.NoteRecord
public typealias BlockRecord = SmartNotesSchemaV5.BlockRecord
public typealias ExternalItemRecord = SmartNotesSchemaV5.ExternalItemRecord
public typealias IntegrationStateRecord = SmartNotesSchemaV5.IntegrationStateRecord

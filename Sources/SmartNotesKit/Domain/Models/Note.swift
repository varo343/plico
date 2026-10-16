import Foundation

/// One logical editor block (paragraph, heading, list item, checklist item...).
public struct NoteBlock: Identifiable, Hashable, Sendable {
    public static let maxIndentLevel = 4

    public let id: UUID
    public var type: BlockType
    /// Fractional-index sort key; see `Rank`.
    public var rank: String
    public var content: RichText
    /// Meaningful for `.checklistItem` only.
    public var isChecked: Bool
    public var indentLevel: Int {
        didSet { indentLevel = Self.clampIndent(indentLevel) }
    }

    public init(
        id: UUID = UUID(),
        type: BlockType = .paragraph,
        rank: String,
        content: RichText = .empty,
        isChecked: Bool = false,
        indentLevel: Int = 0
    ) {
        self.id = id
        self.type = type
        self.rank = rank
        self.content = content
        self.isChecked = isChecked
        self.indentLevel = Self.clampIndent(indentLevel)
    }

    private static func clampIndent(_ level: Int) -> Int {
        min(max(level, 0), maxIndentLevel)
    }
}

/// A user-authored note. Value type; persistence is handled by `NoteRepository`.
public struct Note: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var title: String
    public var createdAt: Date
    public var updatedAt: Date
    public var isPinned: Bool
    public var deletedAt: Date?
    public var priority: Priority
    public var plannedDate: LocalDay?
    public var dueDate: LocalDay?
    public var manualRank: String
    public var sourceExternalItemId: UUID?
    /// Always kept ordered by `rank`.
    public var blocks: [NoteBlock] {
        didSet { blocks.sort { $0.rank < $1.rank } }
    }

    public init(
        id: UUID = UUID(),
        title: String = "",
        createdAt: Date,
        updatedAt: Date? = nil,
        isPinned: Bool = false,
        deletedAt: Date? = nil,
        priority: Priority = .none,
        plannedDate: LocalDay? = nil,
        dueDate: LocalDay? = nil,
        manualRank: String,
        sourceExternalItemId: UUID? = nil,
        blocks: [NoteBlock] = []
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.isPinned = isPinned
        self.deletedAt = deletedAt
        self.priority = priority
        self.plannedDate = plannedDate
        self.dueDate = dueDate
        self.manualRank = manualRank
        self.sourceExternalItemId = sourceExternalItemId
        self.blocks = blocks.sorted { $0.rank < $1.rank }
    }

    public var isTrashed: Bool { deletedAt != nil }

    /// Plain text of the body, one block per line.
    public var bodyPlainText: String {
        blocks.map(\.content.plainText).joined(separator: "\n")
    }

    /// Display-only fallback: explicit title, else first non-empty body line,
    /// else "Untitled". Never written back to `title`.
    public var displayTitle: String {
        NoteText.displayTitle(title: title, body: bodyPlainText)
    }

    /// A copy with fresh note and block IDs and fresh timestamps; content,
    /// formatting and metadata are preserved. The copy is never in Trash.
    public func duplicated(now: Date, manualRank: String) -> Note {
        Note(
            title: title,
            createdAt: now,
            updatedAt: now,
            isPinned: isPinned,
            deletedAt: nil,
            priority: priority,
            plannedDate: plannedDate,
            dueDate: dueDate,
            manualRank: manualRank,
            sourceExternalItemId: sourceExternalItemId,
            blocks: blocks.map {
                NoteBlock(type: $0.type, rank: $0.rank, content: $0.content, isChecked: $0.isChecked, indentLevel: $0.indentLevel)
            }
        )
    }
}

/// Lightweight projection used by lists (no block payloads loaded).
public struct NoteSummary: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var title: String
    /// Title, or first non-empty body line when untitled.
    public var displayTitle: String
    public var preview: String
    public var createdAt: Date
    public var updatedAt: Date
    public var isPinned: Bool
    public var deletedAt: Date?
    public var priority: Priority
    public var plannedDate: LocalDay?
    public var dueDate: LocalDay?
    public var manualRank: String

    public init(
        id: UUID, title: String, displayTitle: String, preview: String, createdAt: Date, updatedAt: Date,
        isPinned: Bool, deletedAt: Date?, priority: Priority,
        plannedDate: LocalDay?, dueDate: LocalDay?, manualRank: String
    ) {
        self.id = id
        self.title = title
        self.displayTitle = displayTitle
        self.preview = preview
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isPinned = isPinned
        self.deletedAt = deletedAt
        self.priority = priority
        self.plannedDate = plannedDate
        self.dueDate = dueDate
        self.manualRank = manualRank
    }
}

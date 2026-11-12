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
    public var tag: BlockTag?
    /// Nested text: longer text tucked under this block (e.g. the draft of an
    /// email next to "write the marketing email"), shown when the row is expanded.
    /// Soft line breaks only; `.empty` when the block has none.
    public var detail: RichText
    /// Which column of the note the block sits in: 0 is the left one (the only
    /// one in most notes), 1 the right one.
    public var column: Int {
        didSet { column = Self.clampColumn(column) }
    }
    /// The picture of an `.image` block (its text is the caption), or one
    /// attached to a row (shown under its text); nil otherwise.
    public var image: NoteImage?
    /// The width the picture is shown at, in points (resized by dragging its
    /// corner); nil shows it at its own size, never wider than the column.
    public var imageWidth: Double?

    public static let maxColumn = 1

    public init(
        id: UUID = UUID(),
        type: BlockType = .paragraph,
        rank: String,
        content: RichText = .empty,
        isChecked: Bool = false,
        indentLevel: Int = 0,
        tag: BlockTag? = nil,
        detail: RichText = .empty,
        column: Int = 0,
        image: NoteImage? = nil,
        imageWidth: Double? = nil
    ) {
        self.id = id
        self.type = type
        self.rank = rank
        self.content = content
        self.isChecked = isChecked
        self.indentLevel = Self.clampIndent(indentLevel)
        self.tag = tag
        self.detail = detail
        self.column = Self.clampColumn(column)
        self.image = image
        self.imageWidth = imageWidth
    }

    private static func clampColumn(_ column: Int) -> Int {
        min(max(column, 0), maxColumn)
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
    /// Always kept in reading order: the left column top to bottom, then the
    /// right one. Ranks rise in that same order (see `ordered(_:)`).
    public var blocks: [NoteBlock] {
        didSet { blocks = Self.ordered(blocks) }
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
        self.blocks = Self.ordered(blocks)
    }

    /// Whether the body is split into two columns.
    public var hasColumns: Bool { blocks.contains { $0.column > 0 } }

    /// Blocks sorted by column, then by rank. A right column with no left one
    /// becomes the only column. Ranks are renumbered when they don't rise
    /// through the columns, so inserting between two neighbours always works.
    static func ordered(_ blocks: [NoteBlock]) -> [NoteBlock] {
        var sorted = blocks.sorted { ($0.column, $0.rank) < ($1.column, $1.rank) }
        if let first = sorted.first, first.column > 0 {
            for index in sorted.indices { sorted[index].column = 0 }
        }
        guard zip(sorted, sorted.dropFirst()).contains(where: { $0.rank > $1.rank }) else { return sorted }
        for (index, rank) in zip(sorted.indices, Rank.evenlySpaced(sorted.count)) { sorted[index].rank = rank }
        return sorted
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
                NoteBlock(type: $0.type, rank: $0.rank, content: $0.content, isChecked: $0.isChecked, indentLevel: $0.indentLevel, tag: $0.tag,
                          detail: $0.detail, column: $0.column, image: $0.image, imageWidth: $0.imageWidth)
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

import Foundation

/// Structural block operations (Enter / Backspace). Pure functions on `Note`
/// so the rules are unit-tested independently of AppKit.
public enum BlockEditing {
    /// The edited note plus where the caret should go next.
    public struct Result: Equatable {
        public var note: Note
        public var focusBlockID: UUID
        public var focusOffset: Int
    }

    public enum Error: Swift.Error {
        case blockNotFound
    }

    /// A note always has at least one block to type into.
    public static func ensuringEditableBlock(_ note: Note) -> Note {
        guard note.blocks.isEmpty else { return note }
        var note = note
        note.blocks = [NoteBlock(rank: Rank.initial)]
        return note
    }

    /// Enter at `offset` in block `blockID`.
    /// - Empty list item: leaves the list (becomes a paragraph).
    /// - Caret at the start of a non-empty block: inserts an empty block above.
    /// - Otherwise: splits; list items continue the list, other kinds continue as paragraph.
    public static func split(_ note: Note, blockID: UUID, atUTF16Offset offset: Int) throws -> Result {
        var note = note
        guard let index = note.blocks.firstIndex(where: { $0.id == blockID }) else { throw Error.blockNotFound }
        let block = note.blocks[index]

        if block.type.isListLike, block.content.isEmpty {
            note.blocks[index].type = .paragraph
            note.blocks[index].indentLevel = 0
            note.blocks[index].isChecked = false
            return Result(note: note, focusBlockID: blockID, focusOffset: 0)
        }

        let continuationType: BlockType = block.type.isListLike ? block.type : .paragraph
        let continuationIndent = block.type.isListLike ? block.indentLevel : 0

        if offset <= 0, !block.content.isEmpty {
            let lower = index > 0 ? note.blocks[index - 1].rank : nil
            let above = NoteBlock(type: continuationType, rank: try Rank.between(lower, block.rank), indentLevel: continuationIndent)
            note.blocks.append(above)
            return Result(note: note, focusBlockID: blockID, focusOffset: 0)
        }

        let (head, tail) = block.content.split(atUTF16Offset: offset)
        let upper = index + 1 < note.blocks.count ? note.blocks[index + 1].rank : nil
        let below = NoteBlock(
            type: continuationType,
            rank: try Rank.between(block.rank, upper),
            content: tail,
            indentLevel: continuationIndent
        )
        note.blocks[index].content = head
        note.blocks.append(below)
        return Result(note: note, focusBlockID: below.id, focusOffset: 0)
    }

    /// Backspace at the very start of block `blockID`.
    /// - A non-paragraph block first turns into a paragraph (content kept).
    /// - A paragraph merges into the previous block, which keeps its own type.
    /// Returns nil when there is nothing to do (first block, already a paragraph).
    public static func mergeWithPrevious(_ note: Note, blockID: UUID) throws -> Result? {
        var note = note
        guard let index = note.blocks.firstIndex(where: { $0.id == blockID }) else { throw Error.blockNotFound }
        let block = note.blocks[index]

        if block.type != .paragraph {
            note.blocks[index].type = .paragraph
            note.blocks[index].indentLevel = 0
            note.blocks[index].isChecked = false
            return Result(note: note, focusBlockID: blockID, focusOffset: 0)
        }
        guard index > 0 else { return nil }

        let previous = note.blocks[index - 1]
        let joinOffset = previous.content.utf16Length
        note.blocks[index - 1].content = previous.content + block.content
        note.blocks.remove(at: index)
        return Result(note: note, focusBlockID: previous.id, focusOffset: joinOffset)
    }

    // MARK: - Block-level commands

    /// Changes a block's kind. Checked state only survives on checklist items;
    /// indentation only on list items.
    public static func setType(_ note: Note, blockID: UUID, to type: BlockType) -> Note? {
        guard let index = note.blocks.firstIndex(where: { $0.id == blockID }), note.blocks[index].type != type else { return nil }
        var note = note
        note.blocks[index].type = type
        if type != .checklistItem { note.blocks[index].isChecked = false }
        if !type.supportsIndent { note.blocks[index].indentLevel = 0 }
        return note
    }

    /// Tab / Shift+Tab. Only list items indent; returns nil when nothing changes.
    public static func indent(_ note: Note, blockID: UUID, by delta: Int) -> Note? {
        guard let index = note.blocks.firstIndex(where: { $0.id == blockID }), note.blocks[index].type.supportsIndent else { return nil }
        var note = note
        let before = note.blocks[index].indentLevel
        note.blocks[index].indentLevel = before + delta
        return note.blocks[index].indentLevel == before ? nil : note
    }

    /// Move Up (-1) / Move Down (+1). Only the moved block's rank changes, so
    /// its content, formatting and checked state are untouched.
    public static func move(_ note: Note, blockID: UUID, by offset: Int) -> Note? {
        guard let index = note.blocks.firstIndex(where: { $0.id == blockID }) else { return nil }
        let target = index + offset
        guard offset != 0, note.blocks.indices.contains(target) else { return nil }
        let otherID = note.blocks[target].id
        return move(note, blockID: blockID, relativeTo: otherID, placeAfter: offset > 0)
    }

    /// Drag and drop: places `blockID` directly before or after `targetID`.
    public static func move(_ note: Note, blockID: UUID, relativeTo targetID: UUID, placeAfter: Bool) -> Note? {
        guard blockID != targetID,
              let moving = note.blocks.first(where: { $0.id == blockID }) else { return nil }
        let orderBefore = note.blocks.map(\.id)
        let others = note.blocks.filter { $0.id != blockID }
        guard let targetIndex = others.firstIndex(where: { $0.id == targetID }) else { return nil }
        let insertion = placeAfter ? targetIndex + 1 : targetIndex
        let lower = insertion > 0 ? others[insertion - 1].rank : nil
        let upper = insertion < others.count ? others[insertion].rank : nil

        var note = note
        let ranksAreUnique = Set(note.blocks.map(\.rank)).count == note.blocks.count
        if ranksAreUnique, let rank = try? Rank.between(lower, upper) {
            guard let index = note.blocks.firstIndex(where: { $0.id == blockID }) else { return nil }
            note.blocks[index].rank = rank
        } else {
            // Duplicate or unusable ranks: renumber everything in the new order.
            var ordered = others
            ordered.insert(moving, at: insertion)
            note.blocks = zip(ordered, Rank.evenlySpaced(ordered.count)).map { block, rank in
                var block = block
                block.rank = rank
                return block
            }
        }
        // Dropping a block where it already is changes nothing.
        return note.blocks.map(\.id) == orderBefore ? nil : note
    }

    /// Inserts pasted paragraphs at `range` in block `blockID`.
    /// One paragraph is inserted inline; several split the block, with the
    /// first joining the text before the caret and the last the text after it.
    public static func paste(_ note: Note, blockID: UUID, range: Range<Int>, paragraphs: [PastedParagraph]) throws -> Result? {
        guard !paragraphs.isEmpty else { return nil }
        var note = note
        guard let index = note.blocks.firstIndex(where: { $0.id == blockID }) else { throw Error.blockNotFound }
        let block = note.blocks[index]
        let (head, rest) = block.content.split(atUTF16Offset: range.lowerBound)
        let tail = rest.split(atUTF16Offset: range.count).tail

        if paragraphs.count == 1 {
            let inserted = paragraphs[0].content
            note.blocks[index].content = head + inserted + tail
            return Result(note: note, focusBlockID: blockID, focusOffset: head.utf16Length + inserted.utf16Length)
        }

        // Pasting a list into an empty block adopts the list's kind.
        if block.content.isEmpty, block.type == .paragraph {
            note.blocks[index].type = paragraphs[0].type
            note.blocks[index].indentLevel = paragraphs[0].type.supportsIndent ? paragraphs[0].indentLevel : 0
            note.blocks[index].isChecked = paragraphs[0].type == .checklistItem && paragraphs[0].isChecked
        }
        note.blocks[index].content = head + paragraphs[0].content

        var lower = block.rank
        let upper = index + 1 < note.blocks.count ? note.blocks[index + 1].rank : nil
        var lastID = blockID
        var lastOffset = 0
        for (position, paragraph) in paragraphs.enumerated().dropFirst() {
            let isLast = position == paragraphs.count - 1
            let rank = try Rank.between(lower, upper)
            let content = isLast ? paragraph.content + tail : paragraph.content
            let newBlock = NoteBlock(
                type: paragraph.type, rank: rank, content: content,
                isChecked: paragraph.type == .checklistItem && paragraph.isChecked,
                indentLevel: paragraph.type.supportsIndent ? paragraph.indentLevel : 0
            )
            note.blocks.append(newBlock)
            lower = rank
            lastID = newBlock.id
            lastOffset = paragraph.content.utf16Length
        }
        return Result(note: note, focusBlockID: lastID, focusOffset: lastOffset)
    }

    /// Ranks grow by a character every so often when inserting repeatedly at the
    /// same spot. Past `maxLength`, all blocks are renumbered evenly.
    public static func normalizingRanks(_ note: Note, maxLength: Int = 24) -> Note {
        guard note.blocks.contains(where: { $0.rank.count > maxLength }) else { return note }
        var note = note
        note.blocks = zip(note.blocks, Rank.evenlySpaced(note.blocks.count)).map { block, rank in
            var block = block
            block.rank = rank
            return block
        }
        return note
    }
}

/// One paragraph of pasted content, already mapped to supported kinds and marks.
public struct PastedParagraph: Equatable, Sendable, Codable {
    public var type: BlockType
    public var content: RichText
    public var indentLevel: Int
    public var isChecked: Bool

    public init(type: BlockType = .paragraph, content: RichText, indentLevel: Int = 0, isChecked: Bool = false) {
        self.type = type
        self.content = content
        self.indentLevel = indentLevel
        self.isChecked = isChecked
    }
}

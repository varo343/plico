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
}

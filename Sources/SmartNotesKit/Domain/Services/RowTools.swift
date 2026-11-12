import Foundation

/// Duplicating rows (the row menu, ⌥-drag). Pure functions on `Note`, like
/// the rest of BlockEditing.
extension BlockEditing {
    /// A copy of the block with a new ID: same kind, text, tag, nested text,
    /// picture and column.
    static func copy(of block: NoteBlock) -> NoteBlock {
        NoteBlock(
            type: block.type, rank: block.rank, content: block.content, isChecked: block.isChecked,
            indentLevel: block.indentLevel, tag: block.tag, detail: block.detail, column: block.column,
            image: block.image, imageWidth: block.imageWidth
        )
    }

    /// Duplicate: the copy goes right below the block. The caret goes to its end.
    public static func duplicate(_ note: Note, blockID: UUID) -> Result? {
        duplicate(note, blockID: blockID, relativeTo: blockID, placeAfter: true)
    }

    /// ⌥-drag: the copy goes before or after `targetID`, in that block's
    /// column; the original stays where it is.
    public static func duplicate(_ note: Note, blockID: UUID, relativeTo targetID: UUID, placeAfter: Bool) -> Result? {
        guard let block = note.blocks.first(where: { $0.id == blockID }) else { return nil }
        return insertBlocks(note, [copy(of: block)], relativeTo: targetID, placeAfter: placeAfter, replacingEmptyLine: false)
    }

    /// ⌥-drag beside the note: the copy goes to the end of `column` (starting it).
    public static func duplicate(_ note: Note, blockID: UUID, toColumn column: Int) -> Result? {
        guard let block = note.blocks.first(where: { $0.id == blockID }) else { return nil }
        var copy = copy(of: block)
        copy.column = min(max(column, 0), NoteBlock.maxColumn)
        var ordered = note.blocks
        let end = (ordered.lastIndex { $0.column <= copy.column }).map { $0 + 1 } ?? 0
        ordered.insert(copy, at: end)
        var updated = note
        updated.blocks = renumbered(ordered)
        return Result(note: updated, focusBlockID: copy.id, focusOffset: copy.content.utf16Length)
    }

    /// Whole blocks as paragraphs, for Copy Row.
    public static func paragraphs(of note: Note, blockIDs: [UUID]) -> [PastedParagraph] {
        let ids = Set(blockIDs)
        return note.blocks.filter { ids.contains($0.id) }.map { block in
            PastedParagraph(type: block.type, content: block.content, indentLevel: block.indentLevel, isChecked: block.isChecked,
                            tag: block.tag, detail: block.detail.isEmpty ? nil : block.detail,
                            image: block.image, imageWidth: block.imageWidth)
        }
    }
}

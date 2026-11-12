import Foundation

/// Two-column notes and pictures. Pure functions on `Note`, like the rest of
/// BlockEditing.
extension BlockEditing {
    /// The blocks of each column, left to right (one array for a one-column note).
    public static func columns(of note: Note) -> [[NoteBlock]] {
        var columns: [[NoteBlock]] = []
        for block in note.blocks {
            if columns.isEmpty || columns[columns.count - 1][0].column != block.column {
                columns.append([block])
            } else {
                columns[columns.count - 1].append(block)
            }
        }
        return columns
    }

    /// Moves blocks to the end of `column`, keeping their order. Moving every
    /// block of the left column makes the right one the only column again.
    /// Returns nil when nothing changes.
    public static func moveToColumn(_ note: Note, blockIDs: [UUID], column: Int) -> Note? {
        let ids = Set(blockIDs)
        let column = min(max(column, 0), NoteBlock.maxColumn)
        var moving = note.blocks.filter { ids.contains($0.id) && $0.column != column }
        guard !moving.isEmpty else { return nil }
        for index in moving.indices { moving[index].column = column }
        var others = note.blocks.filter { !ids.contains($0.id) || $0.column == column }
        let end = (others.lastIndex { $0.column <= column }).map { $0 + 1 } ?? 0
        others.insert(contentsOf: moving, at: end)
        var updated = note
        updated.blocks = renumbered(others)
        return updated
    }

    /// Inserts `blocks` before or after `targetID`, in its column. When the
    /// target is an empty paragraph (a fresh line), the first block takes its
    /// place. The caret goes to the end of the last inserted block.
    public static func insertBlocks(_ note: Note, _ blocks: [NoteBlock], relativeTo targetID: UUID, placeAfter: Bool,
                                    replacingEmptyLine: Bool = true) -> Result? {
        guard !blocks.isEmpty, let targetIndex = note.blocks.firstIndex(where: { $0.id == targetID }) else { return nil }
        let target = note.blocks[targetIndex]
        let replacesTarget = replacingEmptyLine && target.type == .paragraph && target.content.isEmpty && target.detail.isEmpty
            && target.tag == nil && target.image == nil
        var inserted = blocks
        for index in inserted.indices { inserted[index].column = target.column }
        var ordered = note.blocks
        if replacesTarget {
            ordered.replaceSubrange(targetIndex...targetIndex, with: inserted)
        } else {
            ordered.insert(contentsOf: inserted, at: placeAfter ? targetIndex + 1 : targetIndex)
        }
        var updated = note
        updated.blocks = renumbered(ordered)
        let last = inserted[inserted.count - 1]
        return Result(note: updated, focusBlockID: last.id, focusOffset: last.content.utf16Length)
    }

    /// Dropped or pasted pictures, as image blocks placed before or after `targetID`.
    public static func insertImages(_ note: Note, _ images: [NoteImage], relativeTo targetID: UUID, placeAfter: Bool) -> Result? {
        insertBlocks(note, images.map { NoteBlock(type: .image, rank: Rank.initial, image: $0) }, relativeTo: targetID, placeAfter: placeAfter)
    }

    /// Pictures dropped beside the note: they start its right column.
    public static func insertImagesInNewColumn(_ note: Note, _ images: [NoteImage]) -> Result? {
        guard !images.isEmpty, !note.hasColumns else { return nil }
        let blocks = images.map { NoteBlock(type: .image, rank: Rank.initial, column: 1, image: $0) }
        var updated = note
        updated.blocks = renumbered(note.blocks + blocks)
        return Result(note: updated, focusBlockID: blocks[blocks.count - 1].id, focusOffset: 0)
    }

    /// Deletes a block. The caret goes to the end of the block above it in the
    /// same column, else to the start of the one below, else to a fresh line.
    public static func removing(_ note: Note, blockID: UUID) -> Result? {
        guard let index = note.blocks.firstIndex(where: { $0.id == blockID }) else { return nil }
        let column = note.blocks[index].column
        var updated = note
        updated.blocks.remove(at: index)
        updated = ensuringEditableBlock(updated)
        let blocks = updated.blocks
        if index > 0, blocks.indices.contains(index - 1), blocks[index - 1].column == column {
            return Result(note: updated, focusBlockID: blocks[index - 1].id, focusOffset: blocks[index - 1].content.utf16Length)
        }
        if blocks.indices.contains(index), blocks[index].column == column {
            return Result(note: updated, focusBlockID: blocks[index].id, focusOffset: 0)
        }
        // The column is gone: the end of the column before it.
        let fallback = blocks[max(0, min(index, blocks.count) - 1)]
        return Result(note: updated, focusBlockID: fallback.id, focusOffset: fallback.content.utf16Length)
    }

    /// A picture's width in points (nil: its own size); nil when nothing changes.
    public static func setImageWidth(_ note: Note, blockID: UUID, to width: Double?) -> Note? {
        guard let index = note.blocks.firstIndex(where: { $0.id == blockID }), note.blocks[index].image != nil else { return nil }
        let width = width.map { max(32, $0.rounded()) }
        guard note.blocks[index].imageWidth != width else { return nil }
        var note = note
        note.blocks[index].imageWidth = width
        return note
    }

    // MARK: Pictures attached to rows

    /// Whether `targetID` can take a dropped picture: a row (not a picture) without one.
    public static func canAttachImage(_ note: Note, to targetID: UUID) -> Bool {
        note.blocks.first { $0.id == targetID }.map { $0.type != .image && $0.image == nil } ?? false
    }

    /// An image block dropped onto a row: the picture (and its size) moves
    /// under the row's text; a caption joins the row's nested text.
    public static func attachImage(_ note: Note, imageBlockID: UUID, to targetID: UUID) -> Note? {
        guard imageBlockID != targetID, canAttachImage(note, to: targetID),
              let block = note.blocks.first(where: { $0.id == imageBlockID }), block.type == .image, let image = block.image,
              let target = note.blocks.firstIndex(where: { $0.id == targetID }) else { return nil }
        var note = note
        note.blocks[target].image = image
        note.blocks[target].imageWidth = block.imageWidth
        note.blocks[target].detail = joiningDetails(note.blocks[target].detail, block.content)
        note.blocks.removeAll { $0.id == imageBlockID }
        return note
    }

    /// A row's picture dragged onto another row.
    public static func moveAttachedImage(_ note: Note, from rowID: UUID, to targetID: UUID) -> Note? {
        guard rowID != targetID, canAttachImage(note, to: targetID),
              let row = note.blocks.firstIndex(where: { $0.id == rowID }), note.blocks[row].type != .image,
              let image = note.blocks[row].image,
              let target = note.blocks.firstIndex(where: { $0.id == targetID }) else { return nil }
        var note = note
        note.blocks[target].image = image
        note.blocks[target].imageWidth = note.blocks[row].imageWidth
        note.blocks[row].image = nil
        note.blocks[row].imageWidth = nil
        return note
    }

    /// A row's picture dragged out between rows: an image block again, placed
    /// before or after `targetID` (which may be the row it came from).
    public static func detachImage(_ note: Note, from rowID: UUID, relativeTo targetID: UUID, placeAfter: Bool) -> Result? {
        guard let row = note.blocks.firstIndex(where: { $0.id == rowID }), note.blocks[row].type != .image,
              let image = note.blocks[row].image, note.blocks.contains(where: { $0.id == targetID }) else { return nil }
        var note = note
        let width = note.blocks[row].imageWidth
        note.blocks[row].image = nil
        note.blocks[row].imageWidth = nil
        let picture = NoteBlock(type: .image, rank: Rank.initial, image: image, imageWidth: width)
        guard var result = insertBlocks(note, [picture], relativeTo: targetID, placeAfter: placeAfter, replacingEmptyLine: false) else { return nil }
        result.focusOffset = 0
        return result
    }

    /// Removes a row's attached picture (an image block is deleted with `removing`).
    public static func removeAttachedImage(_ note: Note, from rowID: UUID) -> Note? {
        guard let row = note.blocks.firstIndex(where: { $0.id == rowID }), note.blocks[row].type != .image,
              note.blocks[row].image != nil else { return nil }
        var note = note
        note.blocks[row].image = nil
        note.blocks[row].imageWidth = nil
        return note
    }

    /// `blocks` in this order with fresh, evenly spaced ranks.
    static func renumbered(_ blocks: [NoteBlock]) -> [NoteBlock] {
        zip(blocks, Rank.evenlySpaced(blocks.count)).map { block, rank in
            var block = block
            block.rank = rank
            return block
        }
    }
}

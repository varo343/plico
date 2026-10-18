import Foundation

/// A caret position inside a note: block plus UTF-16 offset.
public struct BlockPosition: Equatable, Hashable, Sendable {
    public var blockID: UUID
    public var offset: Int

    public init(blockID: UUID, offset: Int) {
        self.blockID = blockID
        self.offset = offset
    }
}

/// A text selection that spans several blocks (mouse drag across rows, ⌘A twice).
/// `anchor` is where the drag started; `focus` follows the pointer.
public struct BlockRangeSelection: Equatable, Sendable {
    public var anchor: BlockPosition
    public var focus: BlockPosition

    public init(anchor: BlockPosition, focus: BlockPosition) {
        self.anchor = anchor
        self.focus = focus
    }
}

/// One block's share of a multi-block selection.
public struct BlockSegment: Equatable, Sendable {
    public var blockID: UUID
    public var range: Range<Int>
}

// Multi-block selections. Pure functions on `Note`, like the rest of BlockEditing.
extension BlockEditing {
    /// The selection's start and end in document order, offsets clamped.
    /// Nil when a block is missing.
    public static func ordered(_ selection: BlockRangeSelection, in note: Note) -> (start: BlockPosition, end: BlockPosition, startIndex: Int, endIndex: Int)? {
        guard let a = note.blocks.firstIndex(where: { $0.id == selection.anchor.blockID }),
              let f = note.blocks.firstIndex(where: { $0.id == selection.focus.blockID }) else { return nil }
        func clamped(_ position: BlockPosition, _ index: Int) -> BlockPosition {
            BlockPosition(blockID: position.blockID, offset: min(max(position.offset, 0), note.blocks[index].content.utf16Length))
        }
        let anchor = clamped(selection.anchor, a), focus = clamped(selection.focus, f)
        if a < f || (a == f && anchor.offset <= focus.offset) {
            return (anchor, focus, a, f)
        }
        return (focus, anchor, f, a)
    }

    /// The selected range inside each covered block, top to bottom.
    public static func segments(of selection: BlockRangeSelection, in note: Note) -> [BlockSegment] {
        guard let (start, end, startIndex, endIndex) = ordered(selection, in: note) else { return [] }
        return (startIndex...endIndex).map { index in
            let block = note.blocks[index]
            let lower = index == startIndex ? start.offset : 0
            let upper = index == endIndex ? end.offset : block.content.utf16Length
            return BlockSegment(blockID: block.id, range: lower..<max(lower, upper))
        }
    }

    /// Deletes the selected text. The first block keeps its kind and gains the
    /// text after the selection in the last block; blocks in between go away.
    public static func deleteRange(_ note: Note, selection: BlockRangeSelection) throws -> Result {
        guard let (start, end, startIndex, endIndex) = ordered(selection, in: note) else { throw Error.blockNotFound }
        var note = note
        let head = note.blocks[startIndex].content.split(atUTF16Offset: start.offset).head
        let tail = note.blocks[endIndex].content.split(atUTF16Offset: end.offset).tail
        note.blocks[startIndex].content = head + tail
        if endIndex > startIndex {
            note.blocks.removeSubrange((startIndex + 1)...endIndex)
        }
        return Result(note: note, focusBlockID: start.blockID, focusOffset: head.utf16Length)
    }

    /// The selection as paragraphs, keeping each block's kind, indent and check state.
    public static func copiedParagraphs(_ note: Note, selection: BlockRangeSelection) -> [PastedParagraph] {
        segments(of: selection, in: note).compactMap { segment in
            guard let block = note.blocks.first(where: { $0.id == segment.blockID }) else { return nil }
            let content = block.content.split(atUTF16Offset: segment.range.lowerBound).tail
                .split(atUTF16Offset: segment.range.count).head
            return PastedParagraph(type: block.type, content: content, indentLevel: block.indentLevel, isChecked: block.isChecked)
        }
    }

    /// Plain text for other apps: one line per block, lists keep a readable marker.
    public static func plainText(of paragraphs: [PastedParagraph]) -> String {
        var number = 0
        var previous: BlockType?
        return paragraphs.map { paragraph in
            let indent = String(repeating: "  ", count: paragraph.indentLevel)
            number = paragraph.type == .numberedItem ? (previous == .numberedItem ? number + 1 : 1) : 0
            previous = paragraph.type
            let text = paragraph.content.plainText
            switch paragraph.type {
            case .bulletItem: return indent + "- " + text
            case .numberedItem: return indent + "\(number). " + text
            case .checklistItem: return indent + (paragraph.isChecked ? "- [x] " : "- [ ] ") + text
            default: return text
            }
        }.joined(separator: "\n")
    }
}

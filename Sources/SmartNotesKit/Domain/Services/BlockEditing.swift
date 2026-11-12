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
            let above = NoteBlock(type: continuationType, rank: try Rank.between(lower, block.rank), indentLevel: continuationIndent,
                                  column: block.column)
            note.blocks.append(above)
            return Result(note: note, focusBlockID: blockID, focusOffset: 0)
        }

        let (head, tail) = block.content.split(atUTF16Offset: offset)
        let upper = index + 1 < note.blocks.count ? note.blocks[index + 1].rank : nil
        let below = NoteBlock(
            type: continuationType,
            rank: try Rank.between(block.rank, upper),
            content: tail,
            indentLevel: continuationIndent,
            column: block.column
        )
        note.blocks[index].content = head
        note.blocks.append(below)
        return Result(note: note, focusBlockID: below.id, focusOffset: 0)
    }

    /// Backspace at the very start of block `blockID`.
    /// - A picture with no caption goes; with a caption, nothing happens.
    /// - A non-paragraph block first turns into a paragraph (content kept).
    /// - A paragraph merges into the previous block, which keeps its own type.
    ///   It never merges across columns: an empty first block of the right
    ///   column goes instead (and the column with it, when it was alone).
    /// - After a picture, the caret moves to its caption (an empty paragraph goes).
    /// Returns nil when there is nothing to do (first block, already a paragraph).
    public static func mergeWithPrevious(_ note: Note, blockID: UUID) throws -> Result? {
        var note = note
        guard let index = note.blocks.firstIndex(where: { $0.id == blockID }) else { throw Error.blockNotFound }
        let block = note.blocks[index]

        if block.type == .image {
            return block.content.isEmpty ? removing(note, blockID: blockID) : nil
        }
        if block.type != .paragraph {
            note.blocks[index].type = .paragraph
            note.blocks[index].indentLevel = 0
            note.blocks[index].isChecked = false
            return Result(note: note, focusBlockID: blockID, focusOffset: 0)
        }
        let isBlank = block.content.isEmpty && block.detail.isEmpty && block.tag == nil
        guard index > 0, note.blocks[index - 1].column == block.column else {
            return block.column > 0 && isBlank ? removing(note, blockID: blockID) : nil
        }

        let previous = note.blocks[index - 1]
        if previous.type == .image {
            if isBlank { note.blocks.remove(at: index) }
            return Result(note: note, focusBlockID: previous.id, focusOffset: previous.content.utf16Length)
        }
        // A row holds one picture: two rows with one each stay apart.
        if previous.image != nil, block.image != nil { return nil }
        let joinOffset = previous.content.utf16Length
        note.blocks[index - 1].content = previous.content + block.content
        note.blocks[index - 1].tag = previous.tag ?? block.tag
        note.blocks[index - 1].detail = joiningDetails(previous.detail, block.detail)
        if let image = block.image {
            note.blocks[index - 1].image = image
            note.blocks[index - 1].imageWidth = block.imageWidth
        }
        note.blocks.remove(at: index)
        return Result(note: note, focusBlockID: previous.id, focusOffset: joinOffset)
    }

    // MARK: - Block-level commands

    /// Changes a block's kind. Checked state only survives on checklist items;
    /// indentation only on list items. Pictures keep their kind (a picture is
    /// added with `insertImages`, and removed by deleting its block).
    public static func setType(_ note: Note, blockID: UUID, to type: BlockType) -> Note? {
        guard let index = note.blocks.firstIndex(where: { $0.id == blockID }), note.blocks[index].type != type,
              type != .image, note.blocks[index].type != .image else { return nil }
        var note = note
        note.blocks[index].type = type
        if type != .checklistItem { note.blocks[index].isChecked = false }
        if !type.supportsIndent { note.blocks[index].indentLevel = 0 }
        return note
    }

    /// Sets or clears (`nil`) a block's tag; returns nil when nothing changes.
    public static func setTag(_ note: Note, blockID: UUID, to tag: BlockTag?) -> Note? {
        guard let index = note.blocks.firstIndex(where: { $0.id == blockID }), note.blocks[index].tag != tag else { return nil }
        var note = note
        note.blocks[index].tag = tag
        return note
    }

    /// Replaces a block's nested text (`.empty` removes it); returns nil when nothing changes.
    public static func setDetail(_ note: Note, blockID: UUID, to detail: RichText) -> Note? {
        guard let index = note.blocks.firstIndex(where: { $0.id == blockID }), note.blocks[index].detail != detail else { return nil }
        var note = note
        note.blocks[index].detail = detail
        return note
    }

    /// Drag onto another row: the dragged block becomes the last line of that
    /// row's nested text (its own nested text and tag come along) and leaves the note.
    /// A picture dropped onto a row is attached to it instead (see `attachImage`).
    /// A row's own attached picture comes along when the row has none.
    public static func nest(_ note: Note, blockID: UUID, into targetID: UUID) -> Note? {
        guard blockID != targetID,
              let block = note.blocks.first(where: { $0.id == blockID }),
              let targetIndex = note.blocks.firstIndex(where: { $0.id == targetID }),
              note.blocks[targetIndex].type != .image else { return nil }
        if block.type == .image { return attachImage(note, imageBlockID: blockID, to: targetID) }
        guard block.image == nil || note.blocks[targetIndex].image == nil else { return nil }
        let line = nestedText(from: [PastedParagraph(type: block.type, content: block.content, indentLevel: 0, isChecked: block.isChecked,
                                                     tag: block.tag, detail: block.detail)])
        var note = note
        note.blocks[targetIndex].detail = joiningDetails(note.blocks[targetIndex].detail, line)
        if let image = block.image {
            note.blocks[targetIndex].image = image
            note.blocks[targetIndex].imageWidth = block.imageWidth
        }
        note.blocks.removeAll { $0.id == blockID }
        return note
    }

    /// Both blocks' nested text when two blocks become one, so none is lost.
    static func joiningDetails(_ first: RichText, _ second: RichText) -> RichText {
        if first.isEmpty { return second }
        if second.isEmpty { return first }
        return first + RichText(plain: "\n") + second
    }

    /// Pasted paragraphs as nested text: one line each, lists keep a readable
    /// marker, a tag follows as "[High]", and their own nested text follows
    /// indented. Text is never dropped.
    public static func nestedText(from paragraphs: [PastedParagraph]) -> RichText {
        var lines: [RichText] = []
        var number = 0
        var previous: BlockType?
        for paragraph in paragraphs {
            let indent = String(repeating: "    ", count: paragraph.indentLevel)
            number = paragraph.type == .numberedItem ? (previous == .numberedItem ? number + 1 : 1) : 0
            previous = paragraph.type
            let marker = switch paragraph.type {
            case .bulletItem: "• "
            case .numberedItem: "\(number). "
            case .checklistItem: paragraph.isChecked ? "☑ " : "☐ "
            default: ""
            }
            let style = paragraph.content.runs.first.map { TextRun("", fontFamily: $0.fontFamily, fontSize: $0.fontSize) } ?? TextRun("")
            var prefix = style
            prefix.text = indent + marker
            var line = RichText(runs: [prefix]) + paragraph.content
            if let tag = paragraph.tag {
                var label = style
                label.text = " [\(tag.label)]"
                line = line + RichText(runs: [label])
            }
            lines.append(line)
            if let detail = paragraph.detail, !detail.isEmpty {
                prefix.text = indent + "    "
                // Every line, so it all reads as belonging to this one.
                let parts = detail.plainText.split(separator: "\n", omittingEmptySubsequences: false)
                var start = 0
                for part in parts {
                    let length = part.utf16.count
                    lines.append(RichText(runs: [prefix]) + detail.slice(start..<start + length))
                    start += length + 1
                }
            }
        }
        return lines.dropFirst().reduce(lines.first ?? .empty) { $0 + RichText(plain: "\n") + $1 }
    }

    /// Tab / Shift+Tab. Only list items indent; returns nil when nothing changes.
    public static func indent(_ note: Note, blockID: UUID, by delta: Int) -> Note? {
        guard let index = note.blocks.firstIndex(where: { $0.id == blockID }), note.blocks[index].type.supportsIndent else { return nil }
        var note = note
        let before = note.blocks[index].indentLevel
        note.blocks[index].indentLevel = before + delta
        return note.blocks[index].indentLevel == before ? nil : note
    }

    /// Move Up (-1) / Move Down (+1), within the block's column. Only the moved
    /// block's rank changes, so its content, formatting and checked state are untouched.
    public static func move(_ note: Note, blockID: UUID, by offset: Int) -> Note? {
        guard let index = note.blocks.firstIndex(where: { $0.id == blockID }) else { return nil }
        let target = index + offset
        guard offset != 0, note.blocks.indices.contains(target), note.blocks[target].column == note.blocks[index].column else { return nil }
        let otherID = note.blocks[target].id
        return move(note, blockID: blockID, relativeTo: otherID, placeAfter: offset > 0)
    }

    /// Drag and drop: places `blockID` directly before or after `targetID`,
    /// in that block's column.
    public static func move(_ note: Note, blockID: UUID, relativeTo targetID: UUID, placeAfter: Bool) -> Note? {
        guard blockID != targetID,
              var moving = note.blocks.first(where: { $0.id == blockID }) else { return nil }
        let orderBefore = note.blocks.map(\.id)
        let columnsBefore = note.blocks.map(\.column)
        let others = note.blocks.filter { $0.id != blockID }
        guard let targetIndex = others.firstIndex(where: { $0.id == targetID }) else { return nil }
        moving.column = others[targetIndex].column
        let insertion = placeAfter ? targetIndex + 1 : targetIndex
        let lower = insertion > 0 ? others[insertion - 1].rank : nil
        let upper = insertion < others.count ? others[insertion].rank : nil

        var note = note
        let ranksAreUnique = Set(note.blocks.map(\.rank)).count == note.blocks.count
        if ranksAreUnique, let rank = try? Rank.between(lower, upper) {
            guard let index = note.blocks.firstIndex(where: { $0.id == blockID }) else { return nil }
            // Rank and column in one change, so the block is sorted only once, into place.
            moving.rank = rank
            note.blocks[index] = moving
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
        return note.blocks.map(\.id) == orderBefore && note.blocks.map(\.column) == columnsBefore ? nil : note
    }

    /// Inserts pasted paragraphs at `range` in block `blockID`.
    /// One paragraph is inserted inline; several split the block, with the
    /// first joining the text before the caret and the last the text after it.
    public static func paste(_ note: Note, blockID: UUID, range: Range<Int>, paragraphs: [PastedParagraph]) throws -> Result? {
        guard !paragraphs.isEmpty else { return nil }
        // Pictures can't go inside a line of text: everything goes in below as blocks.
        if paragraphs.contains(where: { $0.image != nil }) {
            return insertBlocks(note, paragraphs.map(block(from:)), relativeTo: blockID, placeAfter: true)
        }
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
            note.blocks[index].tag = paragraphs[0].tag
        }
        note.blocks[index].content = head + paragraphs[0].content
        note.blocks[index].detail = joiningDetails(block.detail, paragraphs[0].detail ?? .empty)

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
                indentLevel: paragraph.type.supportsIndent ? paragraph.indentLevel : 0,
                tag: paragraph.tag,
                detail: paragraph.detail ?? .empty,
                column: block.column
            )
            note.blocks.append(newBlock)
            lower = rank
            lastID = newBlock.id
            lastOffset = paragraph.content.utf16Length
        }
        return Result(note: note, focusBlockID: lastID, focusOffset: lastOffset)
    }

    /// A new block for a pasted paragraph (rank and column are set where it goes in).
    static func block(from paragraph: PastedParagraph) -> NoteBlock {
        // An image block without its picture is just its caption.
        let type = paragraph.type == .image && paragraph.image == nil ? .paragraph : paragraph.type
        return NoteBlock(
            type: type, rank: Rank.initial, content: paragraph.content,
            isChecked: type == .checklistItem && paragraph.isChecked,
            indentLevel: type.supportsIndent ? paragraph.indentLevel : 0,
            tag: paragraph.tag, detail: paragraph.detail ?? .empty,
            image: paragraph.image,
            imageWidth: paragraph.image == nil ? nil : paragraph.imageWidth
        )
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
    /// Optional, so pasteboard data written before tags existed still decodes.
    public var tag: BlockTag?
    /// The block's nested text; optional for the same reason.
    public var detail: RichText?
    /// The picture of a copied image block, and the width it was shown at.
    public var image: NoteImage?
    public var imageWidth: Double?

    public init(
        type: BlockType = .paragraph, content: RichText, indentLevel: Int = 0, isChecked: Bool = false,
        tag: BlockTag? = nil, detail: RichText? = nil, image: NoteImage? = nil,
        imageWidth: Double? = nil
    ) {
        self.type = type
        self.content = content
        self.indentLevel = indentLevel
        self.isChecked = isChecked
        self.tag = tag
        self.detail = detail
        self.image = image
        self.imageWidth = imageWidth
    }
}

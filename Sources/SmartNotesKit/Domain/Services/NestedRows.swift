import Foundation

/// Nested text read as rows, so a row tucked into another one can be dragged
/// out again: back into the note as a block, or into another row's nested text.
extension BlockEditing {
    /// The draggable rows of nested text, as UTF-16 ranges: each non-blank line
    /// together with the more indented (or blank) lines under it, which are its
    /// own nested text. Blank lines between rows belong to no row.
    public static func nestedRows(in detail: RichText) -> [Range<Int>] {
        let lines = Self.lines(of: detail.plainText)
        var rows: [Range<Int>] = []
        var index = 0
        while index < lines.count {
            let head = lines[index]
            guard !head.isBlank else {
                index += 1
                continue
            }
            var end = index
            var next = index + 1
            while next < lines.count, lines[next].isBlank || lines[next].leading > head.leading {
                if !lines[next].isBlank { end = next }
                next += 1
            }
            rows.append(head.range.lowerBound..<lines[end].range.upperBound)
            index = end + 1
        }
        return rows
    }

    /// One nested row read back as a block, undoing `nestedText(from:)`: the
    /// "• ", "1. ", "☐ " / "☑ " markers give the kind, a trailing "[High]" the
    /// tag, and the lines under it become its nested text. Formatting is kept.
    public static func paragraph(fromNestedRow row: RichText) -> PastedParagraph {
        let text = row.plainText
        let headEnd = (text as NSString).range(of: "\n").location
        let head = headEnd == NSNotFound ? row : row.slice(0..<headEnd)
        let rest = headEnd == NSNotFound ? RichText.empty : row.slice(headEnd + 1..<row.utf16Length)

        let headText = head.plainText as NSString
        let leading = Self.leadingSpaces(head.plainText)
        var start = leading
        var type = BlockType.paragraph
        var isChecked = false
        let afterIndent = headText.substring(from: leading)
        if let match = afterIndent.firstMatch(of: #/^(?:[•\-\*] |\d{1,9}[.)] |([☐☑]) )/#) {
            if let box = match.output.1 {
                type = .checklistItem
                isChecked = box == "☑"
            } else {
                type = match.output.0.first?.isNumber == true ? .numberedItem : .bulletItem
            }
            start += match.output.0.utf16.count
        }
        var end = headText.length
        var tag: BlockTag?
        if let match = headText.substring(from: start).firstMatch(of: #/ \[([^\[\]\n]{1,24})\]$/#), let named = BlockTag.named(String(match.output.1)) {
            tag = named
            end -= match.output.0.utf16.count
        }
        return PastedParagraph(
            type: type,
            content: head.slice(start..<end),
            indentLevel: type.supportsIndent ? leading / 4 : 0,
            isChecked: isChecked,
            tag: tag,
            detail: dedented(rest)
        )
    }

    /// Drag a nested row back into the note, as a block placed before or after
    /// `targetID` (which may be the row it came from).
    public static func unnest(_ note: Note, blockID: UUID, row: Range<Int>, relativeTo targetID: UUID, placeAfter: Bool) -> Result? {
        guard let index = note.blocks.firstIndex(where: { $0.id == blockID }),
              let rowText = nestedRow(note.blocks[index].detail, row),
              note.blocks.contains(where: { $0.id == targetID }) else { return nil }
        let paragraph = paragraph(fromNestedRow: rowText)
        var note = note
        note.blocks[index].detail = removingNestedRow(note.blocks[index].detail, row)
        let others = note.blocks
        guard let targetIndex = others.firstIndex(where: { $0.id == targetID }) else { return nil }
        let insertion = placeAfter ? targetIndex + 1 : targetIndex
        let lower = insertion > 0 ? others[insertion - 1].rank : nil
        let upper = insertion < others.count ? others[insertion].rank : nil
        var block = NoteBlock(
            type: paragraph.type, rank: Rank.initial, content: paragraph.content,
            isChecked: paragraph.isChecked, indentLevel: paragraph.indentLevel,
            tag: paragraph.tag, detail: paragraph.detail ?? .empty,
            column: others[targetIndex].column
        )
        if let rank = try? Rank.between(lower, upper) {
            block.rank = rank
            note.blocks.append(block)
        } else {
            // No room between the neighbours' ranks: renumber everything.
            var ordered = others
            ordered.insert(block, at: insertion)
            note.blocks = zip(ordered, Rank.evenlySpaced(ordered.count)).map { block, rank in
                var block = block
                block.rank = rank
                return block
            }
        }
        return Result(note: note, focusBlockID: block.id, focusOffset: paragraph.content.utf16Length)
    }

    /// Drag a nested row onto another row: it becomes the last row of that
    /// row's nested text, as it was written.
    public static func moveNestedRow(_ note: Note, blockID: UUID, row: Range<Int>, into targetID: UUID) -> Note? {
        guard blockID != targetID,
              let index = note.blocks.firstIndex(where: { $0.id == blockID }),
              let targetIndex = note.blocks.firstIndex(where: { $0.id == targetID }),
              let rowText = nestedRow(note.blocks[index].detail, row) else { return nil }
        var note = note
        note.blocks[index].detail = removingNestedRow(note.blocks[index].detail, row)
        note.blocks[targetIndex].detail = joiningDetails(note.blocks[targetIndex].detail, rowText)
        return note
    }

    /// The row's text when `row` is one of `detail`'s rows.
    private static func nestedRow(_ detail: RichText, _ row: Range<Int>) -> RichText? {
        guard !row.isEmpty, row.upperBound <= detail.utf16Length else { return nil }
        return detail.slice(row)
    }

    /// `detail` without the row and one line break next to it, so no blank
    /// line is left behind.
    static func removingNestedRow(_ detail: RichText, _ row: Range<Int>) -> RichText {
        let text = detail.plainText.utf16
        let newline = "\n".utf16.first!
        var removed = row
        if row.upperBound < text.count, text[text.index(text.startIndex, offsetBy: row.upperBound)] == newline {
            removed = row.lowerBound..<row.upperBound + 1
        } else if row.lowerBound > 0, text[text.index(text.startIndex, offsetBy: row.lowerBound - 1)] == newline {
            removed = row.lowerBound - 1..<row.upperBound
        }
        return detail.replacing(removed, with: .empty)
    }

    /// Lines shifted left by their common indentation.
    private static func dedented(_ text: RichText) -> RichText? {
        guard !text.isEmpty else { return nil }
        let lines = Self.lines(of: text.plainText)
        let indent = lines.filter { !$0.isBlank }.map(\.leading).min() ?? 0
        let parts = lines.map { line in
            text.slice(min(line.range.lowerBound + indent, line.range.upperBound)..<line.range.upperBound)
        }
        let joined = parts.dropFirst().reduce(parts[0]) { $0 + RichText(plain: "\n") + $1 }
        return joined.isEmpty ? nil : joined
    }

    private struct Line {
        var range: Range<Int>
        var leading: Int
        var isBlank: Bool
    }

    private static func lines(of text: String) -> [Line] {
        var lines: [Line] = []
        var offset = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let length = line.utf16.count
            lines.append(Line(
                range: offset..<offset + length,
                leading: leadingSpaces(String(line)),
                isBlank: line.allSatisfy(\.isWhitespace)
            ))
            offset += length + 1
        }
        return lines
    }

    private static func leadingSpaces(_ line: String) -> Int {
        line.prefix { $0 == " " }.count
    }
}

extension RichText {
    /// The text in a UTF-16 range, with its formatting.
    func slice(_ range: Range<Int>) -> RichText {
        split(atUTF16Offset: range.upperBound).head.split(atUTF16Offset: range.lowerBound).tail
    }
}

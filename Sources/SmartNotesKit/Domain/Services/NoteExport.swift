import Foundation

/// Portable exports of user-authored notes. JSON is a lossless backup;
/// Markdown is for reading and moving notes to other apps.
public enum NoteExport {
    // MARK: JSON

    public struct Document: Codable, Equatable {
        public var format = "smart-notes-export"
        public var version = 1
        public var exportedAt: Date
        public var notes: [ExportedNote]
    }

    public struct ExportedNote: Codable, Equatable {
        public var id: UUID
        public var title: String
        public var createdAt: Date
        public var updatedAt: Date
        public var deletedAt: Date?
        public var isPinned: Bool
        public var priority: Priority
        public var plannedDate: LocalDay?
        public var dueDate: LocalDay?
        public var blocks: [ExportedBlock]
    }

    public struct ExportedBlock: Codable, Equatable {
        public var type: BlockType
        public var content: RichText
        public var isChecked: Bool
        public var indentLevel: Int
        /// Omitted when the block has no tag.
        public var tag: BlockTag?
        /// Nested text; omitted when the block has none.
        public var detail: RichText?
        /// 1 for the right column; omitted for the left (or only) one.
        public var column: Int?
        /// An image block's picture, or a row's attached one (Base64 in the file); omitted otherwise.
        public var image: Data?
        /// The picture's chosen width in points; omitted at its own size.
        public var imageWidth: Double?
    }

    public static func json(_ notes: [Note], exportedAt: Date) throws -> Data {
        let document = Document(exportedAt: exportedAt, notes: notes.map { note in
            ExportedNote(
                id: note.id, title: note.title, createdAt: note.createdAt, updatedAt: note.updatedAt,
                deletedAt: note.deletedAt, isPinned: note.isPinned, priority: note.priority,
                plannedDate: note.plannedDate, dueDate: note.dueDate,
                blocks: note.blocks.map {
                    ExportedBlock(type: $0.type, content: $0.content, isChecked: $0.isChecked, indentLevel: $0.indentLevel,
                                  tag: $0.tag, detail: $0.detail.isEmpty ? nil : $0.detail,
                                  column: $0.column == 0 ? nil : $0.column, image: $0.image?.data, imageWidth: $0.image == nil ? nil : $0.imageWidth)
                }
            )
        })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(document)
    }

    // MARK: Markdown

    /// One note as Markdown with a small front-matter block for its metadata.
    public static func markdown(_ note: Note) -> String {
        var lines: [String] = []
        var front: [String] = []
        if note.priority != .none { front.append("priority: \(note.priority.rawValue)") }
        if let planned = note.plannedDate { front.append("planned: \(planned.isoString)") }
        if let due = note.dueDate { front.append("due: \(due.isoString)") }
        if note.isPinned { front.append("pinned: true") }
        if !front.isEmpty { lines += ["---"] + front + ["---", ""] }

        lines.append("# " + escapeLine(note.displayTitle))
        lines.append("")

        var number = 0
        var previous: BlockType?
        for block in note.blocks {
            let text = inline(block.content) + (block.tag.map { " " + hashtag($0) } ?? "")
            let indent = String(repeating: "  ", count: block.indentLevel)
            number = block.type == .numberedItem ? (previous == .numberedItem ? number + 1 : 1) : 0
            // Blank line between non-list blocks so Markdown keeps them apart.
            if let previous, !(previous.isListLike && block.type.isListLike) { lines.append("") }
            switch block.type {
            case .paragraph: lines.append(text)
            case .heading1: lines.append("## " + text)
            case .heading2: lines.append("### " + text)
            case .heading3: lines.append("#### " + text)
            case .bulletItem: lines.append(indent + "- " + text)
            case .numberedItem: lines.append(indent + "\(number). " + text)
            case .checklistItem: lines.append(indent + (block.isChecked ? "- [x] " : "- [ ] ") + text)
            case .quote: lines.append(text.split(separator: "\n", omittingEmptySubsequences: false).map { "> " + $0 }.joined(separator: "\n"))
            // The picture itself is in the JSON export; Markdown names it.
            case .image: lines.append("*[Image" + (block.content.isEmpty ? "" : ": " + text) + "]*")
            }
            // A picture attached to a row, named under it.
            if block.type != .image, block.image != nil { lines.append(indent + (block.type.isListLike ? "  " : "") + "*[Image]*") }
            // Nested text: a quote under its block, indented to stay part of a list item.
            if !block.detail.isEmpty {
                let nestedIndent = block.type.isListLike ? indent + "  " : ""
                if !block.type.isListLike { lines.append("") }
                // Splitting after the "  " of each hard break keeps the breaks inside the quote.
                lines += inline(block.detail).split(separator: "\n", omittingEmptySubsequences: false).map { nestedIndent + "> " + $0 }
            }
            previous = block.type
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// File name for a note: its title made safe for the file system, unique within `used`.
    public static func fileName(for note: Note, used: inout Set<String>) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:?%*|\"<>").union(.newlines).union(.controlCharacters)
        var base = note.displayTitle.components(separatedBy: forbidden).joined(separator: "-")
            .trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: ".")))
        if base.isEmpty { base = NoteText.untitled }
        base = String(base.prefix(80))
        var name = base + ".md"
        var counter = 2
        while used.contains(name.lowercased()) {
            name = "\(base) \(counter).md"
            counter += 1
        }
        used.insert(name.lowercased())
        return name
    }

    private static func inline(_ text: RichText) -> String {
        text.runs.map { run in
            // Soft line breaks become Markdown hard breaks.
            var value = escapeInline(run.text).replacingOccurrences(of: "\n", with: "  \n")
            if run.marks.contains(.code) { value = "`" + run.text + "`" }
            if run.marks.contains(.bold) { value = "**" + value + "**" }
            if run.marks.contains(.italic) { value = "*" + value + "*" }
            if run.marks.contains(.strikethrough) { value = "~~" + value + "~~" }
            if run.marks.contains(.underline) { value = "<u>" + value + "</u>" }
            if let link = run.link { value = "[" + value + "](" + link.absoluteString + ")" }
            return value
        }.joined()
    }

    /// "#high", "#client-review": readable in other Markdown apps that use hashtags.
    private static func hashtag(_ tag: BlockTag) -> String {
        let words = tag.label.lowercased().components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        return "#" + escapeInline(words.joined(separator: "-"))
    }

    private static func escapeInline(_ text: String) -> String {
        var result = ""
        for character in text {
            if "\\`*_[]<>~".contains(character) { result.append("\\") }
            result.append(character)
        }
        return result
    }

    private static func escapeLine(_ text: String) -> String {
        escapeInline(text).replacingOccurrences(of: "\n", with: " ")
    }
}

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
    }

    public static func json(_ notes: [Note], exportedAt: Date) throws -> Data {
        let document = Document(exportedAt: exportedAt, notes: notes.map { note in
            ExportedNote(
                id: note.id, title: note.title, createdAt: note.createdAt, updatedAt: note.updatedAt,
                deletedAt: note.deletedAt, isPinned: note.isPinned, priority: note.priority,
                plannedDate: note.plannedDate, dueDate: note.dueDate,
                blocks: note.blocks.map { ExportedBlock(type: $0.type, content: $0.content, isChecked: $0.isChecked, indentLevel: $0.indentLevel) }
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
            let text = inline(block.content)
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

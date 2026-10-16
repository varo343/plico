import Foundation

/// "/checkbox", "/bullet"… typed in a block turn it into that kind.
public struct SlashCommand: Equatable, Sendable, Identifiable {
    public let name: String
    public let aliases: [String]
    public let title: String
    public let type: BlockType

    public var id: String { name }

    public static let all: [SlashCommand] = [
        SlashCommand(name: "text", aliases: ["paragraph", "body", "testo"], title: "Text", type: .paragraph),
        SlashCommand(name: "h1", aliases: ["heading", "heading1", "title", "titolo"], title: "Heading 1", type: .heading1),
        SlashCommand(name: "h2", aliases: ["heading2", "subheading"], title: "Heading 2", type: .heading2),
        SlashCommand(name: "h3", aliases: ["heading3"], title: "Heading 3", type: .heading3),
        SlashCommand(name: "checkbox", aliases: ["check", "checklist", "todo", "task"], title: "Checklist", type: .checklistItem),
        SlashCommand(name: "bullet", aliases: ["list", "bullets", "ul", "elenco"], title: "Bulleted list", type: .bulletItem),
        SlashCommand(name: "numbered", aliases: ["number", "ol", "numeri"], title: "Numbered list", type: .numberedItem),
        SlashCommand(name: "quote", aliases: ["blockquote", "citazione"], title: "Quote", type: .quote),
    ]

    /// Commands whose name or an alias starts with `query` (case-insensitive);
    /// name matches rank before alias matches. An empty query lists all.
    public static func matches(_ query: String) -> [SlashCommand] {
        let q = query.lowercased()
        guard !q.isEmpty else { return all }
        let byName = all.filter { $0.name.hasPrefix(q) }
        let byAlias = all.filter { command in !byName.contains(command) && command.aliases.contains { $0.hasPrefix(q) } }
        return byName + byAlias
    }

    /// The command named exactly `query` (name or alias), if any.
    public static func exact(_ query: String) -> SlashCommand? {
        let q = query.lowercased()
        return all.first { $0.name == q || $0.aliases.contains(q) }
    }
}

/// Finds the "/query" being typed at the caret.
public enum SlashTrigger {
    public struct Token: Equatable, Sendable {
        /// UTF-16 range from the "/" to the caret.
        public var range: Range<Int>
        public var query: String
    }

    private static let maxQueryLength = 20

    /// A token exists when the caret follows "/" plus letters/digits, and the
    /// "/" starts the block or follows whitespace (so URLs and "1/2" don't trigger).
    public static func token(in text: String, caret: Int) -> Token? {
        let units = Array(text.utf16)
        guard caret > 0, caret <= units.count else { return nil }
        var index = caret - 1
        while index >= 0, caret - index <= maxQueryLength + 1 {
            let unit = units[index]
            if unit == 0x2F { // "/"
                if index > 0, let previous = UnicodeScalar(units[index - 1]), !CharacterSet.whitespacesAndNewlines.contains(previous) {
                    return nil
                }
                let query = String(utf16CodeUnits: Array(units[(index + 1)..<caret]), count: caret - index - 1)
                return Token(range: index..<caret, query: query)
            }
            guard let scalar = UnicodeScalar(unit), CharacterSet.alphanumerics.contains(scalar) else { return nil }
            index -= 1
        }
        return nil
    }

    /// "/name " just typed (exact command followed by a space): apply immediately.
    /// Returns the command and the range to remove, including the space.
    public static func completedCommand(in text: String, caret: Int) -> (SlashCommand, Range<Int>)? {
        let units = Array(text.utf16)
        guard caret >= 2, caret <= units.count, units[caret - 1] == 0x20,
              let token = token(in: text, caret: caret - 1),
              let command = SlashCommand.exact(token.query) else { return nil }
        return (command, token.range.lowerBound..<caret)
    }
}

extension BlockEditing {
    /// Removes the typed "/command" text and turns the block into `type`.
    public static func applySlashCommand(_ note: Note, blockID: UUID, removing range: Range<Int>, type: BlockType) throws -> Result {
        guard let index = note.blocks.firstIndex(where: { $0.id == blockID }) else { throw Error.blockNotFound }
        var note = note
        note.blocks[index].content = note.blocks[index].content.replacing(range, with: .empty)
        note = setType(note, blockID: blockID, to: type) ?? note
        return Result(note: note, focusBlockID: blockID, focusOffset: range.lowerBound)
    }
}

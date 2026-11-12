import Foundation

/// "/checkbox", "/bullet"… typed in a block turn it into that kind;
/// "/nested" adds nested text under it; "/high", "/medium", "/low", "/custom"
/// (all found by "/tag") tag it.
public struct SlashCommand: Equatable, Sendable, Identifiable {
    public enum Action: Equatable, Sendable {
        case turnInto(BlockType)
        case tag(BlockTag)
        /// Asks for a custom tag name.
        case customTag
        case removeTag
        /// Opens the block's nested text, ready to write.
        case nestedText
        /// Moves the block to the note's other column (starting it if needed).
        case otherColumn
        /// Asks for pictures to put in below the block.
        case image
    }

    /// Groups in the slash menu, in this order.
    public enum Section: Sendable {
        case turnInto, add, tag
    }

    public let name: String
    public let aliases: [String]
    public let title: String
    public let action: Action

    public var id: String { name }

    /// The block kind this command turns a block into; nil for tag commands.
    public var type: BlockType? {
        if case .turnInto(let type) = action { type } else { nil }
    }

    public var section: Section {
        switch action {
        case .turnInto: .turnInto
        case .nestedText, .otherColumn, .image: .add
        case .tag, .customTag, .removeTag: .tag
        }
    }

    public var isTagCommand: Bool { section == .tag }

    private init(name: String, aliases: [String], title: String, type: BlockType) {
        self.init(name: name, aliases: aliases, title: title, action: .turnInto(type))
    }

    private init(name: String, aliases: [String], title: String, action: Action) {
        self.name = name
        self.aliases = aliases
        self.title = title
        self.action = action
    }

    /// Shared by every tag command, so "/tag" lists them all. Never applied by
    /// itself: it is ambiguous, so `exact` ignores it.
    private static let tagAliases = ["tag", "priority", "severity", "etichetta", "priorita"]

    public static let all: [SlashCommand] = [
        SlashCommand(name: "text", aliases: ["paragraph", "body", "testo"], title: "Text", type: .paragraph),
        SlashCommand(name: "h1", aliases: ["heading", "heading1", "title", "titolo"], title: "Heading 1", type: .heading1),
        SlashCommand(name: "h2", aliases: ["heading2", "subheading"], title: "Heading 2", type: .heading2),
        SlashCommand(name: "h3", aliases: ["heading3"], title: "Heading 3", type: .heading3),
        SlashCommand(name: "checkbox", aliases: ["check", "checklist", "todo", "task"], title: "Checklist", type: .checklistItem),
        SlashCommand(name: "bullet", aliases: ["list", "bullets", "ul", "elenco"], title: "Bulleted list", type: .bulletItem),
        SlashCommand(name: "numbered", aliases: ["number", "ol", "numeri"], title: "Numbered list", type: .numberedItem),
        SlashCommand(name: "quote", aliases: ["blockquote", "citazione"], title: "Quote", type: .quote),
        SlashCommand(name: "nested", aliases: ["nest", "detail", "details", "toggle", "innestato", "dettagli"], title: "Nested text",
                     action: .nestedText),
        SlashCommand(name: "image", aliases: ["picture", "photo", "img", "immagine", "foto"], title: "Image…", action: .image),
        SlashCommand(name: "column", aliases: ["columns", "split", "colonna", "colonne"], title: "Move to other column",
                     action: .otherColumn),
        SlashCommand(name: "high", aliases: tagAliases + ["urgent", "alta", "p1"], title: "High", action: .tag(.priority(.high))),
        SlashCommand(name: "medium", aliases: tagAliases + ["media", "p2"], title: "Medium", action: .tag(.priority(.medium))),
        SlashCommand(name: "low", aliases: tagAliases + ["bassa", "p3"], title: "Low", action: .tag(.priority(.low))),
        SlashCommand(name: "custom", aliases: tagAliases + ["label", "personalizzato"], title: "Custom tag…", action: .customTag),
        SlashCommand(name: "untag", aliases: tagAliases + ["notag", "removetag"], title: "Remove tag", action: .removeTag),
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

    /// The command named exactly `query` (name or alias), if exactly one matches.
    /// "/tag" names several commands, so it opens the menu instead of applying one.
    public static func exact(_ query: String) -> SlashCommand? {
        let q = query.lowercased()
        let found = all.filter { $0.name == q || $0.aliases.contains(q) }
        return found.count == 1 ? found[0] : nil
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
    /// Removes the typed "/command" text and applies the command: changes the
    /// kind or the tag. `.customTag` only removes the text; the name is asked next.
    public static func applySlashCommand(_ note: Note, blockID: UUID, removing range: Range<Int>, action: SlashCommand.Action) throws -> Result {
        guard let index = note.blocks.firstIndex(where: { $0.id == blockID }) else { throw Error.blockNotFound }
        var note = note
        note.blocks[index].content = note.blocks[index].content.replacing(range, with: .empty)
        switch action {
        case .turnInto(let type): note = setType(note, blockID: blockID, to: type) ?? note
        case .tag(let tag): note = setTag(note, blockID: blockID, to: tag) ?? note
        case .removeTag: note = setTag(note, blockID: blockID, to: nil) ?? note
        case .otherColumn:
            let column = note.blocks[index].column == 0 ? 1 : 0
            note = moveToColumn(note, blockIDs: [blockID], column: column) ?? note
        case .customTag, .nestedText, .image: break
        }
        return Result(note: note, focusBlockID: blockID, focusOffset: range.lowerBound)
    }
}

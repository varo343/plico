import Foundation

/// Derived text used for display, previews and search.
public enum NoteText {
    public static let previewLength = 200
    public static let untitled = "Untitled"

    public static func displayTitle(title: String, body: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return nonEmptyLines(body).first ?? untitled
    }

    /// Single-line preview with whitespace collapsed. For an untitled note the
    /// first line is already shown as the title, so it is skipped here.
    public static func preview(title: String, body: String) -> String {
        var lines = nonEmptyLines(body)
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !lines.isEmpty {
            lines.removeFirst()
        }
        let collapsed = lines
            .joined(separator: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        return String(collapsed.prefix(previewLength))
    }

    private static func nonEmptyLines(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Searchable text: title plus all block text, case/diacritic/width folded.
    public static func searchText(title: String, blocks: [NoteBlock]) -> String {
        let body = blocks.map(\.content.plainText).joined(separator: "\n")
        return fold(title + "\n" + body)
    }

    /// Normalization applied to both stored search text and queries, so
    /// "Cafe" matches "Café".
    public static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .lowercased()
    }
}

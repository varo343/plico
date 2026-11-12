import Foundation

/// Turns pasted Markdown (as written by chat assistants, docs and code editors)
/// into blocks and marks: `**bold**`, `*italic*`, `~~strike~~`, `` `code` ``,
/// `[text](url)`, headings, lists, checklists and quotes. Escapes (`\*`) and
/// HTML entities (`&amp;`) become the characters they stand for. Anything it
/// doesn't understand is kept as literal text.
public enum MarkdownImport {
    /// `template` supplies the formatting at the caret (font, size, marks).
    public static func paragraphs(_ string: String, template: TextRun = TextRun("")) -> [PastedParagraph] {
        var base = template
        base.text = ""
        base.link = nil
        let normalized = string.replacingOccurrences(of: "\r\n", with: "\n")
        var lines = normalized.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" || $0 == "\r" || $0 == "\u{2029}" })
            .map(String.init)
        if lines.count > 1, lines.last?.isEmpty == true { lines.removeLast() }

        let unit = indentUnit(lines)
        var result: [PastedParagraph] = []
        var fence: String?
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Fenced code: the fences go, the lines inside stay literal, in code style.
            if let open = fence {
                if trimmed.hasPrefix(open) {
                    fence = nil
                } else {
                    var run = base
                    run.text = line
                    run.marks.insert(.code)
                    result.append(PastedParagraph(content: RichText(runs: [run])))
                }
                continue
            }
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                fence = String(trimmed.prefix(3))
                continue
            }
            if isThematicBreak(trimmed) { continue }
            result.append(paragraph(line, base: base, indentUnit: unit))
        }
        return result
    }

    /// True when `string` contains Markdown syntax worth converting. Used to
    /// decide whether rich pasteboard data without formatting (e.g. from a
    /// code editor or Terminal) is really Markdown source.
    public static func looksLikeMarkdown(_ string: String) -> Bool {
        let patterns = [
            "\\*\\*[^*\\n]+\\*\\*", "__[^_\\n]+__", "~~[^~\\n]+~~", "`[^`\\n]+`",
            "\\[[^\\]\\n]+\\]\\([^)\\s]+\\)",
            "(?m)^\\s{0,3}#{1,6}\\s", "(?m)^\\s*[-*+]\\s+\\[[ xX]\\]\\s", "(?m)^\\s*[-*+]\\s+\\S",
            "(?m)^\\s*\\d{1,9}[.)]\\s+\\S", "(?m)^\\s{0,3}>\\s", "(?m)^\\s*```",
            "&(?:amp|lt|gt|quot|apos|nbsp|#\\d+|#[xX][0-9a-fA-F]+);",
        ]
        return patterns.contains { string.range(of: $0, options: .regularExpression) != nil }
    }

    // MARK: Blocks

    private static func paragraph(_ line: String, base: TextRun, indentUnit: Int) -> PastedParagraph {
        let leading = line.prefix { $0 == " " || $0 == "\t" }
        let width = leading.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
        let body = String(line.dropFirst(leading.count))
        let indent = min(width / max(indentUnit, 1), NoteBlock.maxIndentLevel)

        if let match = body.firstMatch(of: /^(#{1,6})[ \t]+(.*?)(?:[ \t]+#+)?[ \t]*$/) {
            let level = match.1.count
            let type: BlockType = level == 1 ? .heading1 : level == 2 ? .heading2 : .heading3
            return PastedParagraph(type: type, content: inline(String(match.2), base: base))
        }
        if let match = body.firstMatch(of: /^[-*+][ \t]+\[([ xX])\][ \t]+(.*)$/) {
            return PastedParagraph(type: .checklistItem, content: inline(String(match.2), base: base),
                                   indentLevel: indent, isChecked: match.1 != " ")
        }
        if let match = body.firstMatch(of: /^[-*+•][ \t]+(.*)$/) {
            return PastedParagraph(type: .bulletItem, content: inline(String(match.1), base: base), indentLevel: indent)
        }
        if let match = body.firstMatch(of: /^\d{1,9}[.)][ \t]+(.*)$/) {
            return PastedParagraph(type: .numberedItem, content: inline(String(match.1), base: base), indentLevel: indent)
        }
        if width < 4, let match = body.firstMatch(of: /^>[ \t]?(.*)$/) {
            return PastedParagraph(type: .quote, content: inline(String(match.1), base: base))
        }
        // Two trailing spaces are a Markdown line break; here the line ends anyway.
        return PastedParagraph(content: inline(line.replacing(/[ \t]+$/, with: ""), base: base))
    }

    /// Spaces per indent level: the smallest indent used by a list line (2 or 4 in practice).
    private static func indentUnit(_ lines: [String]) -> Int {
        let widths = lines.compactMap { line -> Int? in
            let leading = line.prefix { $0 == " " || $0 == "\t" }
            let rest = line.dropFirst(leading.count)
            guard !leading.isEmpty, rest.firstMatch(of: /^(?:[-*+•]|\d{1,9}[.)])[ \t]/) != nil else { return nil }
            return leading.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
        }
        return min(widths.min() ?? 2, 4)
    }

    /// "---", "***", "___" (optionally spaced) on their own line.
    private static func isThematicBreak(_ trimmed: String) -> Bool {
        let compact = trimmed.filter { $0 != " " }
        guard compact.count >= 3, let first = compact.first, "-*_".contains(first) else { return false }
        return compact.allSatisfy { $0 == first }
    }

    // MARK: Inline

    /// Inline Markdown in one line to formatted runs.
    public static func inline(_ text: String, base: TextRun = TextRun("")) -> RichText {
        var parser = InlineParser(characters: Array(text), base: base)
        return RichText(runs: parser.parse(0..<parser.characters.count, marks: base.marks, link: nil))
    }

    private struct InlineParser {
        let characters: [Character]
        let base: TextRun

        mutating func parse(_ bounds: Range<Int>, marks: Set<InlineMark>, link: URL?) -> [TextRun] {
            var runs: [TextRun] = []
            var buffer = ""
            func flush() {
                guard !buffer.isEmpty else { return }
                runs.append(run(buffer, marks: marks, link: link))
                buffer = ""
            }
            var i = bounds.lowerBound
            let end = bounds.upperBound
            while i < end {
                let c = characters[i]
                switch c {
                case "\\" where i + 1 < end && isEscapable(characters[i + 1]):
                    buffer.append(characters[i + 1])
                    i += 2
                    continue
                case "`":
                    let count = runLength(at: i, of: "`", limit: end)
                    if let close = closingBackticks(from: i + count, count: count, limit: end) {
                        flush()
                        var code = String(characters[(i + count)..<close])
                        if code.count > 2, code.first == " ", code.last == " " { code = String(code.dropFirst().dropLast()) }
                        runs.append(run(code, marks: marks.union([.code]), link: link))
                        i = close + count
                    } else {
                        buffer.append(String(repeating: "`", count: count))
                        i += count
                    }
                    continue
                case "!" where i + 1 < end && characters[i + 1] == "[":
                    // An image keeps only its description.
                    if let (label, _, after) = linkParts(at: i + 1, limit: end) {
                        flush()
                        runs += parse(label, marks: marks, link: link)
                        i = after
                        continue
                    }
                case "[":
                    if let (label, url, after) = linkParts(at: i, limit: end) {
                        flush()
                        runs += parse(label, marks: marks, link: url.flatMap(Self.allowedURL) ?? link)
                        i = after
                        continue
                    }
                case "<":
                    if let (replacement, after) = angleBracket(at: i, limit: end) {
                        flush()
                        runs.append(run(replacement.text, marks: marks, link: replacement.link ?? link))
                        i = after
                        continue
                    }
                case "&":
                    if let (decoded, after) = entity(at: i, limit: end) {
                        buffer += decoded
                        i = after
                        continue
                    }
                case "*", "_", "~":
                    if let (content, mark, after) = emphasis(at: i, limit: end) {
                        flush()
                        runs += parse(content, marks: marks.union(mark), link: link)
                        i = after
                        continue
                    }
                    // An unmatched run stays literal as a whole ("**" never becomes "*" + emphasis).
                    let count = runLength(at: i, of: c, limit: end)
                    buffer.append(String(repeating: c, count: count))
                    i += count
                    continue
                default:
                    break
                }
                buffer.append(c)
                i += 1
            }
            flush()
            return runs
        }

        private func run(_ text: String, marks: Set<InlineMark>, link: URL?) -> TextRun {
            TextRun(text, marks: marks, link: link, fontFamily: base.fontFamily, fontSize: base.fontSize)
        }

        private func isEscapable(_ c: Character) -> Bool {
            c.isASCII && (c.isPunctuation || c.isSymbol)
        }

        private func runLength(at index: Int, of c: Character, limit: Int) -> Int {
            var j = index
            while j < limit, characters[j] == c { j += 1 }
            return j - index
        }

        private func closingBackticks(from start: Int, count: Int, limit: Int) -> Int? {
            var j = start
            while j < limit {
                if characters[j] == "`" {
                    let length = runLength(at: j, of: "`", limit: limit)
                    if length == count { return j }
                    j += length
                } else {
                    j += 1
                }
            }
            return nil
        }

        /// `*a*` / `_a_` italic, `**a**` / `__a__` bold, `***a***` both, `~~a~~` strikethrough.
        /// Openers must be followed, and closers preceded, by non-space; underscores
        /// inside words (snake_case) never count.
        private func emphasis(at index: Int, limit: Int) -> (Range<Int>, Set<InlineMark>, Int)? {
            let c = characters[index]
            let count = runLength(at: index, of: c, limit: limit)
            let marks: Set<InlineMark>
            switch (c, count) {
            case ("~", 2): marks = [.strikethrough]
            case ("*", 1), ("_", 1): marks = [.italic]
            case ("*", 2), ("_", 2): marks = [.bold]
            case ("*", 3), ("_", 3): marks = [.bold, .italic]
            default: return nil
            }
            let contentStart = index + count
            guard contentStart < limit, !characters[contentStart].isWhitespace else { return nil }
            if c == "_", index > 0, isWordCharacter(characters[index - 1]) { return nil }

            var j = contentStart
            while j < limit {
                let current = characters[j]
                if current == "\\" { j += 2; continue }
                if current == "`" {
                    let length = runLength(at: j, of: "`", limit: limit)
                    j = closingBackticks(from: j + length, count: length, limit: limit).map { $0 + length } ?? j + length
                    continue
                }
                guard current == c else { j += 1; continue }
                let length = runLength(at: j, of: c, limit: limit)
                let after = j + length
                if length == count, j > contentStart, !characters[j - 1].isWhitespace,
                   !(c == "_" && after < limit && isWordCharacter(characters[after])) {
                    return (contentStart..<j, marks, after)
                }
                j = after
            }
            return nil
        }

        private func isWordCharacter(_ c: Character) -> Bool {
            c.isLetter || c.isNumber
        }

        /// `[label](url "title")` starting at the "[". The URL is nil when it can't be parsed.
        private func linkParts(at index: Int, limit: Int) -> (Range<Int>, URL?, Int)? {
            var depth = 0
            var j = index
            var labelEnd: Int?
            while j < limit {
                switch characters[j] {
                case "\\": j += 1
                case "[": depth += 1
                case "]":
                    depth -= 1
                    if depth == 0 { labelEnd = j }
                default: break
                }
                if labelEnd != nil { break }
                j += 1
            }
            guard let labelEnd, labelEnd + 1 < limit, characters[labelEnd + 1] == "(" else { return nil }
            var k = labelEnd + 2
            var parens = 1
            while k < limit {
                if characters[k] == "(" { parens += 1 }
                if characters[k] == ")" { parens -= 1; if parens == 0 { break } }
                k += 1
            }
            guard k < limit else { return nil }
            var target = String(characters[(labelEnd + 2)..<k]).trimmingCharacters(in: .whitespaces)
            if let space = target.firstIndex(where: \.isWhitespace) { target = String(target[..<space]) } // drops a "title"
            if target.hasPrefix("<"), target.hasSuffix(">") { target = String(target.dropFirst().dropLast()) }
            return ((index + 1)..<labelEnd, URL(string: target), k + 1)
        }

        /// `<https://…>` / `<name@host>` autolinks and `<br>`.
        private func angleBracket(at index: Int, limit: Int) -> ((text: String, link: URL?), Int)? {
            guard let close = characters[index..<limit].firstIndex(of: ">") else { return nil }
            let inner = String(characters[(index + 1)..<close])
            if inner.range(of: "^br\\s*/?$", options: [.regularExpression, .caseInsensitive]) != nil {
                return (("\n", nil), close + 1)
            }
            guard !inner.isEmpty, !inner.contains(where: \.isWhitespace) else { return nil }
            if inner.contains("://"), let url = URL(string: inner).flatMap(Self.allowedURL) {
                return ((inner, url), close + 1)
            }
            if inner.firstMatch(of: /^[^@\s]+@[^@\s]+\.[^@\s]+$/) != nil, let url = URL(string: "mailto:" + inner).flatMap(Self.allowedURL) {
                return ((inner, url), close + 1)
            }
            return nil
        }

        private static let namedEntities: [String: String] = [
            "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}",
            "ndash": "–", "mdash": "—", "hellip": "…", "laquo": "«", "raquo": "»",
            "lsquo": "‘", "rsquo": "’", "ldquo": "“", "rdquo": "”", "euro": "€", "copy": "©", "reg": "®", "trade": "™",
        ]

        private func entity(at index: Int, limit: Int) -> (String, Int)? {
            let window = characters[index..<min(limit, index + 12)]
            guard let semicolon = window.firstIndex(of: ";") else { return nil }
            let name = String(characters[(index + 1)..<semicolon])
            if let named = Self.namedEntities[name] { return (named, semicolon + 1) }
            let value: UInt32?
            if name.hasPrefix("#x") || name.hasPrefix("#X") {
                value = UInt32(name.dropFirst(2), radix: 16)
            } else if name.hasPrefix("#") {
                value = UInt32(name.dropFirst())
            } else {
                value = nil
            }
            guard let value, value != 0, let scalar = UnicodeScalar(value) else { return nil }
            return (String(Character(scalar)), semicolon + 1)
        }

        private static func allowedURL(_ url: URL) -> URL? {
            LinkValidator.isAllowed(url) ? url : nil
        }
    }
}

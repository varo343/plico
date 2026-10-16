import AppKit
import UniformTypeIdentifiers

extension NSPasteboard.PasteboardType {
    /// Lossless in-app copy of one block's selection (RichText JSON).
    static let smartNotesRichText = NSPasteboard.PasteboardType("local.smartnotes.richtext")
}

/// Reduces pasted HTML to a small allowlist of formatting tags before it is
/// handed to the system HTML importer. All attributes except validated `href`s
/// are dropped and active/embedded content is removed, so importing pasted HTML
/// can't load remote resources (images, stylesheets, frames) or run anything.
enum HTMLSanitizer {
    private static let allowedTags: Set<String> = [
        "a", "b", "strong", "i", "em", "u", "s", "strike", "del", "code", "pre",
        "p", "br", "div", "span", "li", "ul", "ol", "blockquote", "h1", "h2", "h3", "h4", "h5", "h6",
    ]
    private static let droppedWithContent = "script|style|head|title|iframe|object|embed|svg|math|template|noscript|canvas|video|audio"

    static func sanitize(_ html: String) -> String {
        var text = html
        text = text.replacingOccurrences(of: "<!--[\\s\\S]*?-->", with: "", options: .regularExpression)
        text = text.replacingOccurrences(
            of: "<(\(droppedWithContent))\\b[^>]*>[\\s\\S]*?</\\1\\s*>", with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        let tag = try! NSRegularExpression(pattern: "<\\s*(/?)\\s*([a-zA-Z][a-zA-Z0-9]*)([^>]*)>")
        var result = ""
        var cursor = text.startIndex
        for match in tag.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            let range = Range(match.range, in: text)!
            result += text[cursor..<range.lowerBound]
            cursor = range.upperBound
            let closing = !Range(match.range(at: 1), in: text)!.isEmpty
            let name = text[Range(match.range(at: 2), in: text)!].lowercased()
            guard allowedTags.contains(name) else { continue }
            if closing {
                result += "</\(name)>"
            } else if name == "a" {
                let attributes = String(text[Range(match.range(at: 3), in: text)!])
                if let href = href(in: attributes) {
                    result += "<a href=\"\(href)\">"
                } else {
                    result += "<a>"
                }
            } else {
                result += "<\(name)>"
            }
        }
        result += text[cursor...]
        return result
    }

    private static func href(in attributes: String) -> String? {
        let pattern = try! NSRegularExpression(pattern: "href\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s>]+))", options: .caseInsensitive)
        guard let match = pattern.firstMatch(in: attributes, range: NSRange(attributes.startIndex..., in: attributes)) else { return nil }
        let value = (1...3).lazy
            .compactMap { Range(match.range(at: $0), in: attributes) }
            .map { String(attributes[$0]) }
            .first ?? ""
        let decoded = value.replacingOccurrences(of: "&amp;", with: "&")
        guard let url = URL(string: decoded), LinkValidator.isAllowed(url) else { return nil }
        return url.absoluteString
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

/// Maps pasteboard contents to supported blocks and marks. Text is never dropped:
/// unsupported formatting degrades to plain text.
@MainActor
enum PasteConverter {
    /// `template` supplies the formatting at the caret, used for plain text.
    static func paragraphs(from pasteboard: NSPasteboard, plainOnly: Bool, template: TextRun) -> [PastedParagraph]? {
        if !plainOnly {
            if let data = pasteboard.data(forType: .smartNotesRichText), let text = try? RichText.decode(from: data) {
                return [PastedParagraph(content: text)] // copies stay within one block
            }
            if let data = pasteboard.data(forType: .rtf),
               let attributed = NSAttributedString(rtf: data, documentAttributes: nil) {
                return paragraphs(from: attributed)
            }
            if let html = pasteboard.string(forType: .html),
               let data = HTMLSanitizer.sanitize(html).data(using: .utf8),
               let attributed = try? NSAttributedString(
                   data: data,
                   options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue],
                   documentAttributes: nil
               ) {
                return paragraphs(from: attributed)
            }
        }
        guard let string = pasteboard.string(forType: .string) else { return nil }
        return plainParagraphs(string, template: template)
    }

    static func plainParagraphs(_ string: String, template: TextRun) -> [PastedParagraph] {
        let normalized = string.replacingOccurrences(of: "\r\n", with: "\n")
        var lines = normalized.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" || $0 == "\r" || $0 == "\u{2029}" })
        if lines.count > 1, lines.last?.isEmpty == true { lines.removeLast() }
        return lines.map { line in
            var run = template
            run.text = String(line)
            run.link = nil
            return PastedParagraph(content: RichText(runs: [run]))
        }
    }

    static func paragraphs(from attributed: NSAttributedString) -> [PastedParagraph] {
        let string = attributed.string as NSString
        var result: [PastedParagraph] = []
        var location = 0
        while location < string.length {
            let paragraphRange = string.paragraphRange(for: NSRange(location: location, length: 0))
            var contentRange = paragraphRange
            // Drop the paragraph terminator(s).
            while contentRange.length > 0,
                  let scalar = UnicodeScalar(string.character(at: contentRange.upperBound - 1)),
                  CharacterSet.newlines.contains(scalar) {
                contentRange.length -= 1
            }
            result.append(paragraph(in: attributed, range: contentRange))
            location = paragraphRange.upperBound
        }
        return result
    }

    private static func paragraph(in attributed: NSAttributedString, range: NSRange) -> PastedParagraph {
        var type = BlockType.paragraph
        if range.length > 0,
           let style = attributed.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle,
           let list = style.textLists.last {
            type = list.markerFormat == .decimal || list.markerFormat == .lowercaseAlpha || list.markerFormat == .lowercaseRoman
                ? .numberedItem : .bulletItem
        }
        var runs: [TextRun] = []
        attributed.enumerateAttributes(in: range) { attrs, subrange, _ in
            runs.append(TextRun(
                (attributed.string as NSString).substring(with: subrange),
                marks: marks(from: attrs),
                link: link(from: attrs[.link])
            ))
        }
        var content = RichText(runs: runs)
        if type != .paragraph {
            content = removingListMarker(content)
        }
        return PastedParagraph(type: type, content: content)
    }

    private static func marks(from attrs: [NSAttributedString.Key: Any]) -> Set<InlineMark> {
        var marks = Set<InlineMark>()
        if let font = attrs[.font] as? NSFont {
            let traits = font.fontDescriptor.symbolicTraits
            if traits.contains(.bold) { marks.insert(.bold) }
            if traits.contains(.italic) { marks.insert(.italic) }
        }
        if let underline = attrs[.underlineStyle] as? Int, underline != 0 { marks.insert(.underline) }
        if let strike = attrs[.strikethroughStyle] as? Int, strike != 0 { marks.insert(.strikethrough) }
        return marks
    }

    /// Unsafe or malformed links are dropped; their text is kept.
    private static func link(from value: Any?) -> URL? {
        let url = (value as? URL) ?? (value as? String).flatMap(URL.init(string:))
        guard let url, LinkValidator.isAllowed(url) else { return nil }
        return url
    }

    /// The HTML/RTF importers put list markers ("\t•\t", "\t1.\t") into the text.
    private static func removingListMarker(_ content: RichText) -> RichText {
        let text = content.plainText
        guard let match = text.range(of: "^\\t?(?:[•◦▪▫‣⁃–\\-*]|[0-9]+[.)]?|[a-zA-Z][.)]?|[ivxlc]+[.)]?)\\t", options: .regularExpression) else {
            return content
        }
        let length = text[match].utf16.count
        return content.split(atUTF16Offset: length).tail
    }
}

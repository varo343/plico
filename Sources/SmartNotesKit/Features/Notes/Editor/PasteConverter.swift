import AppKit
import UniformTypeIdentifiers

extension NSPasteboard.PasteboardType {
    /// Lossless in-app copy of one block's selection (RichText JSON).
    static let smartNotesRichText = NSPasteboard.PasteboardType("local.smartnotes.richtext")
    /// Lossless in-app copy of a selection spanning several blocks ([PastedParagraph] JSON).
    static let smartNotesBlocks = NSPasteboard.PasteboardType("local.smartnotes.blocks")
}

/// Writing whole blocks to a pasteboard: a lossless copy for Plico plus
/// readable plain text for other apps.
@MainActor
enum BlockClipboard {
    static func write(_ paragraphs: [PastedParagraph], to pasteboard: NSPasteboard = .general) {
        guard !paragraphs.isEmpty else { return }
        pasteboard.clearContents()
        pasteboard.declareTypes([.string, .smartNotesBlocks], owner: nil)
        pasteboard.setString(BlockEditing.plainText(of: paragraphs), forType: .string)
        if let data = try? PasteConverter.encode(paragraphs) {
            pasteboard.setData(data, forType: .smartNotesBlocks)
        }
    }
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
            // A screenshot, a copied image or image files: pictures, one block each.
            let pictures = ImageDrop.immediateData(ImageDrop.payload(from: pasteboard, ignoringText: true)).compactMap { NoteImage.importing($0) }
            if !pictures.isEmpty {
                return pictures.map { PastedParagraph(type: .image, content: .empty, image: $0) }
            }
            if let data = pasteboard.data(forType: .smartNotesBlocks), let paragraphs = try? decode(data), !paragraphs.isEmpty {
                return paragraphs
            }
            if let data = pasteboard.data(forType: .smartNotesRichText), let text = try? RichText.decode(from: data) {
                return [PastedParagraph(content: text)] // copies stay within one block
            }
            if let link = namedLink(from: pasteboard, template: template) {
                return [link]
            }
            if let rich = richParagraphs(from: pasteboard) {
                // Code editors and Terminal put Markdown source on the pasteboard as
                // RTF/HTML with only colours and fonts: read the Markdown instead.
                if !hasFormatting(rich), let string = pasteboard.string(forType: .string), MarkdownImport.looksLikeMarkdown(string) {
                    return MarkdownImport.paragraphs(string, template: template)
                }
                return rich
            }
        }
        guard let string = pasteboard.string(forType: .string) else { return nil }
        // "Paste and Match Style" keeps the text exactly as it is, Markdown symbols included.
        return plainOnly ? plainParagraphs(string, template: template) : MarkdownImport.paragraphs(string, template: template)
    }

    static let urlName = NSPasteboard.PasteboardType("public.url-name")

    /// A web address on its own (copied from the address bar, "Copy Link",
    /// a link dragged from a browser): a link named by the title that came
    /// with it, else by `LinkNaming.readableName` (the editor then looks for
    /// the page's title). Nil when the pasteboard holds anything more.
    static func namedLink(from pasteboard: NSPasteboard, template: TextRun) -> PastedParagraph? {
        let string = pasteboard.string(forType: .string)
        let url = string.flatMap(LinkNaming.standaloneURL(in:))
            ?? (string == nil ? webURL(on: pasteboard) : nil)
        guard let url else { return nil }
        var run = template
        run.link = url
        run.text = linkTitle(on: pasteboard, for: url) ?? LinkNaming.readableName(for: url)
        return PastedParagraph(content: RichText(runs: [run]))
    }

    private static func webURL(on pasteboard: NSPasteboard) -> URL? {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] ?? []
        guard urls.count == 1, let url = urls.first, !url.isFileURL, LinkValidator.isAllowed(url) else { return nil }
        return url
    }

    /// The name that came with the address: Safari's link title, or the text
    /// of the one link in the copied HTML/RTF (Chrome, Edge, web pages).
    private static func linkTitle(on pasteboard: NSPasteboard, for url: URL) -> String? {
        func usable(_ name: String?) -> String? {
            guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty,
                  LinkNaming.standaloneURL(in: name) == nil, name != url.absoluteString else { return nil }
            return name.count > LinkNaming.maxTitleLength ? String(name.prefix(LinkNaming.maxTitleLength - 1)) + "…" : name
        }
        if let name = usable(pasteboard.string(forType: urlName)) { return name }
        guard let rich = richParagraphs(from: pasteboard), rich.count == 1 else { return nil }
        let linked = rich[0].content.runs.filter { $0.link != nil }
        guard !linked.isEmpty, Set(linked.compactMap(\.link)).count == 1 else { return nil }
        return usable(linked.map(\.text).joined())
    }

    private static func richParagraphs(from pasteboard: NSPasteboard) -> [PastedParagraph]? {
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
        return nil
    }

    /// Any mark, link or non-paragraph kind.
    private static func hasFormatting(_ paragraphs: [PastedParagraph]) -> Bool {
        paragraphs.contains { paragraph in
            paragraph.type != .paragraph || paragraph.content.runs.contains { !$0.marks.isEmpty || $0.link != nil }
        }
    }

    static func encode(_ paragraphs: [PastedParagraph]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(paragraphs)
    }

    static func decode(_ data: Data) throws -> [PastedParagraph] {
        try JSONDecoder().decode([PastedParagraph].self, from: data)
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

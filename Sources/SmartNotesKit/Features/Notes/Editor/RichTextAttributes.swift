import AppKit

extension NSAttributedString.Key {
    /// Source of truth for inline marks inside the text view (bitmask of `InlineMark`).
    /// Display attributes (fonts, underline...) are derived from it, never read back.
    static let snMarks = NSAttributedString.Key("SmartNotes.marks")
    static let snFontFamily = NSAttributedString.Key("SmartNotes.fontFamily")
    static let snFontSize = NSAttributedString.Key("SmartNotes.fontSize")
}

/// Editor defaults chosen in Settings (system font, 16 pt unless changed).
public struct EditorDefaults: Equatable, Sendable {
    public var fontFamily: FontFamilyPreset
    public var fontSize: FontSizePreset

    public init(fontFamily: FontFamilyPreset = .system, fontSize: FontSizePreset = .body) {
        self.fontFamily = fontFamily
        self.fontSize = fontSize
    }
}

/// Per-block-type base typography.
struct BlockTextStyle: Equatable {
    var baseSize: CGFloat
    var weight: NSFont.Weight
    var family: FontFamilyPreset
    var lineHeight: CGFloat
    /// Checked checklist items are shown muted.
    var isMuted: Bool

    init(type: BlockType, defaults: EditorDefaults, isChecked: Bool) {
        let body = defaults.fontSize.points
        switch type {
        case .heading1: (baseSize, weight) = (body + 8, .bold)
        case .heading2: (baseSize, weight) = (body + 4, .semibold)
        case .heading3: (baseSize, weight) = (body + 1, .semibold)
        default: (baseSize, weight) = (body, .regular)
        }
        family = defaults.fontFamily
        // Body 16/25 per the design spec; headings a little tighter.
        lineHeight = (baseSize * (type == .paragraph || type.isListLike || type == .quote ? 1.5625 : 1.3)).rounded()
        isMuted = type == .checklistItem && isChecked
    }
}

/// Lossless conversion between `RichText` and the attributed strings in the editor.
enum RichTextAttributes {
    private static let markBits: [(InlineMark, Int)] = [(.bold, 1), (.italic, 2), (.underline, 4), (.strikethrough, 8), (.code, 16)]

    static func attributedString(for text: RichText, style: BlockTextStyle) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for run in text.runs {
            result.append(NSAttributedString(
                string: run.text,
                attributes: attributes(marks: run.marks, link: run.link, family: run.fontFamily, size: run.fontSize, style: style)
            ))
        }
        return result
    }

    static func typingAttributes(style: BlockTextStyle) -> [NSAttributedString.Key: Any] {
        attributes(marks: [], link: nil, family: nil, size: nil, style: style)
    }

    /// Reads only the SmartNotes keys and `.link`; anything else (e.g. pasted
    /// foreign styling) is ignored rather than guessed at. Text is never dropped.
    static func richText(from string: NSAttributedString) -> RichText {
        var runs: [TextRun] = []
        let source = string.string as NSString
        string.enumerateAttributes(in: NSRange(location: 0, length: string.length)) { attrs, range, _ in
            let link: URL? = (attrs[.link] as? URL) ?? (attrs[.link] as? String).flatMap(URL.init(string:))
            runs.append(TextRun(
                source.substring(with: range),
                marks: marks(from: attrs[.snMarks]),
                link: link,
                fontFamily: (attrs[.snFontFamily] as? String).flatMap(FontFamilyPreset.init(rawValue:)),
                fontSize: (attrs[.snFontSize] as? Int).flatMap(FontSizePreset.init(rawValue:))
            ))
        }
        return RichText(runs: runs)
    }

    static func attributes(
        marks: Set<InlineMark>, link: URL?, family: FontFamilyPreset?, size: FontSizePreset?, style: BlockTextStyle
    ) -> [NSAttributedString.Key: Any] {
        let pointSize = size?.points ?? style.baseSize
        let paragraph = NSMutableParagraphStyle()
        let lineHeight = style.lineHeight * pointSize / style.baseSize
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight

        var attrs: [NSAttributedString.Key: Any] = [
            .font: font(
                family: marks.contains(.code) ? .monospaced : (family ?? style.family),
                size: pointSize,
                weight: marks.contains(.bold) ? .bold : style.weight,
                italic: marks.contains(.italic)
            ),
            .foregroundColor: style.isMuted ? NSColor(SNColor.textSecondary) : NSColor(SNColor.textPrimary),
            .paragraphStyle: paragraph,
            // Center glyphs vertically within the fixed line height.
            .baselineOffset: max(0, lineHeight - pointSize * 1.2) / 2,
            .snMarks: bitmask(marks),
        ]
        if marks.contains(.underline) { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        if marks.contains(.strikethrough) { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        if marks.contains(.code) { attrs[.backgroundColor] = NSColor(SNColor.borderSubtle).withAlphaComponent(0.5) }
        if let link { attrs[.link] = link }
        if let family { attrs[.snFontFamily] = family.rawValue }
        if let size { attrs[.snFontSize] = size.rawValue }
        return attrs
    }

    static func font(family: FontFamilyPreset, size: CGFloat, weight: NSFont.Weight, italic: Bool) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        var descriptor = base.fontDescriptor
        let design: NSFontDescriptor.SystemDesign? = switch family {
        case .system: nil
        case .serif: .serif
        case .rounded: .rounded
        case .monospaced: .monospaced
        }
        if let design, let designed = descriptor.withDesign(design) { descriptor = designed }
        if italic { descriptor = descriptor.withSymbolicTraits(descriptor.symbolicTraits.union(.italic)) }
        return NSFont(descriptor: descriptor, size: size) ?? base
    }

    private static func bitmask(_ marks: Set<InlineMark>) -> Int {
        markBits.reduce(0) { marks.contains($1.0) ? $0 | $1.1 : $0 }
    }

    private static func marks(from value: Any?) -> Set<InlineMark> {
        guard let mask = value as? Int else { return [] }
        return Set(markBits.filter { mask & $0.1 != 0 }.map(\.0))
    }
}

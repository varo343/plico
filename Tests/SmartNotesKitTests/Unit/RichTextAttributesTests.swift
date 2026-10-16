import AppKit
import Testing
@testable import SmartNotesKit

/// The editor must round-trip formatting losslessly through NSAttributedString.
@MainActor
@Suite struct RichTextAttributesTests {
    private let style = BlockTextStyle(type: .paragraph, defaults: EditorDefaults(), isChecked: false)

    @Test func roundTripsEveryAttribute() {
        let text = RichText(runs: [
            TextRun("plain "),
            TextRun("bold italic", marks: [.bold, .italic]),
            TextRun(" under", marks: [.underline]),
            TextRun(" strike", marks: [.strikethrough]),
            TextRun(" code", marks: [.code]),
            TextRun(" link", link: URL(string: "https://example.com")),
            TextRun(" serif 22", fontFamily: .serif, fontSize: .title),
            TextRun(" soft\nbreak 👍🏽"),
        ])
        let attributed = RichTextAttributes.attributedString(for: text, style: style)
        #expect(RichTextAttributes.richText(from: attributed) == text)
    }

    @Test(arguments: BlockType.allCases)
    func roundTripsInEveryBlockStyle(type: BlockType) {
        let style = BlockTextStyle(type: type, defaults: EditorDefaults(fontFamily: .rounded, fontSize: .large), isChecked: true)
        let text = RichText(runs: [TextRun("A", marks: [.bold]), TextRun("b")])
        #expect(RichTextAttributes.richText(from: RichTextAttributes.attributedString(for: text, style: style)) == text)
    }

    @Test func foreignAttributesDegradeToPlainTextWithoutLoss() {
        let foreign = NSAttributedString(string: "Pasted from Safari", attributes: [
            .font: NSFont(name: "Times New Roman", size: 30) ?? NSFont.systemFont(ofSize: 30),
            .foregroundColor: NSColor.red,
        ])
        #expect(RichTextAttributes.richText(from: foreign) == RichText(plain: "Pasted from Safari"))
    }

    @Test func displayAttributesReflectMarks() {
        let attributed = RichTextAttributes.attributedString(
            for: RichText(runs: [TextRun("x", marks: [.bold, .italic, .underline, .strikethrough])]), style: style
        )
        let attrs = attributed.attributes(at: 0, effectiveRange: nil)
        let font = attrs[.font] as? NSFont
        #expect(font?.fontDescriptor.symbolicTraits.contains(.bold) == true)
        #expect(font?.fontDescriptor.symbolicTraits.contains(.italic) == true)
        #expect(attrs[.underlineStyle] as? Int == NSUnderlineStyle.single.rawValue)
        #expect(attrs[.strikethroughStyle] as? Int == NSUnderlineStyle.single.rawValue)
        #expect(font?.pointSize == 16)
    }

    @Test func headingsAreLargerThanBody() {
        let defaults = EditorDefaults()
        let sizes = [BlockType.heading1, .heading2, .heading3, .paragraph].map { BlockTextStyle(type: $0, defaults: defaults, isChecked: false).baseSize }
        #expect(sizes == sizes.sorted(by: >))
        #expect(BlockTextStyle(type: .paragraph, defaults: defaults, isChecked: false).lineHeight == 25) // 16/25 spec
    }
}

import AppKit
import Foundation
import Testing
@testable import SmartNotesKit

@Suite struct RichTextRangeTests {
    private let text = RichText(runs: [TextRun("Hello ", marks: [.bold]), TextRun("world")])

    @Test func toggleAddsThenRemoves() {
        let bolded = text.toggling(.bold, in: 3..<9)
        #expect(bolded.runs == [TextRun("Hello wor", marks: [.bold]), TextRun("ld")])
        // Whole range already bold → removing.
        #expect(bolded.toggling(.bold, in: 3..<9).runs == [TextRun("Hel", marks: [.bold]), TextRun("lo world")])
    }

    @Test func toggleOnMixedRangeAddsEverywhere() {
        let italic = text.toggling(.italic, in: 0..<11)
        #expect(italic.runs == [TextRun("Hello ", marks: [.bold, .italic]), TextRun("world", marks: [.italic])])
    }

    @Test func commonMarks() {
        #expect(text.commonMarks(in: 0..<3) == [.bold])
        #expect(text.commonMarks(in: 3..<8).isEmpty)
        #expect(text.commonMarks(in: 2..<2) == [.bold])  // caret inside bold
        #expect(text.commonMarks(in: 8..<8).isEmpty)     // caret inside plain
    }

    @Test func replacingAndLinks() {
        let url = URL(string: "https://example.com")!
        let linked = text.transformingRuns(in: 6..<11) { $0.link = url }
        #expect(linked.commonLink(in: 6..<11) == url)
        #expect(linked.commonLink(in: 0..<11) == nil)
        #expect(text.replacing(0..<5, with: RichText(plain: "Bye")).plainText == "Bye world")
    }

    @Test func otherFormattingSurvivesEveryOperation() {
        let rich = RichText(runs: [TextRun("ab", marks: [.underline], fontFamily: .serif, fontSize: .large), TextRun("cd", link: URL(string: "https://a.b"))])
        let toggled = rich.toggling(.bold, in: 1..<3)
        #expect(toggled.runs[0] == TextRun("a", marks: [.underline], fontFamily: .serif, fontSize: .large))
        #expect(toggled.runs[1] == TextRun("b", marks: [.underline, .bold], fontFamily: .serif, fontSize: .large))
        #expect(toggled.runs[2].link == URL(string: "https://a.b"))
        #expect(toggled.plainText == "abcd")
    }
}

@Suite struct EditHistoryTests {
    private let t0 = Date(timeIntervalSince1970: 0)
    private func snapshot(_ text: String) -> EditHistory.Snapshot {
        EditHistory.Snapshot(blocks: [NoteBlock(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, rank: "i", content: RichText(plain: text))], caret: nil)
    }

    @Test func typingInSameBlockCoalesces() {
        var history = EditHistory()
        let block = UUID()
        history.record(before: snapshot(""), kind: .typing(blockID: block), at: t0)
        history.record(before: snapshot("a"), kind: .typing(blockID: block), at: t0.addingTimeInterval(0.5))
        history.record(before: snapshot("ab"), kind: .typing(blockID: block), at: t0.addingTimeInterval(1))
        #expect(history.undoStack.count == 1)
        #expect(history.undo(current: snapshot("abc")) == snapshot(""))
        #expect(history.redo(current: snapshot("")) == snapshot("abc"))
    }

    @Test func pauseOtherBlockOrStructuralBreaksCoalescing() {
        var history = EditHistory()
        let a = UUID(), b = UUID()
        history.record(before: snapshot("1"), kind: .typing(blockID: a), at: t0)
        history.record(before: snapshot("2"), kind: .typing(blockID: a), at: t0.addingTimeInterval(5)) // pause
        history.record(before: snapshot("3"), kind: .typing(blockID: b), at: t0.addingTimeInterval(5.1)) // other block
        history.record(before: snapshot("4"), kind: .structural, at: t0.addingTimeInterval(5.2))
        history.record(before: snapshot("5"), kind: .structural, at: t0.addingTimeInterval(5.3))
        #expect(history.undoStack.count == 5)
    }

    @Test func newEditClearsRedoAndLimitIsEnforced() {
        var history = EditHistory(limit: 3)
        for i in 0..<10 { history.record(before: snapshot("\(i)"), kind: .structural, at: t0) }
        #expect(history.undoStack.count == 3)
        _ = history.undo(current: snapshot("x"))
        #expect(history.canRedo)
        history.record(before: snapshot("y"), kind: .structural, at: t0)
        #expect(!history.canRedo)
    }
}

@Suite struct LinkValidatorTests {
    @Test(arguments: [
        ("https://example.com/a?b=1", "https://example.com/a?b=1"),
        ("example.com", "https://example.com"),
        ("  www.apple.com/mac  ", "https://www.apple.com/mac"),
        ("http://localhost:8080", "http://localhost:8080"),
        ("ada@example.com", "mailto:ada@example.com"),
        ("mailto:ada@example.com", "mailto:ada@example.com"),
    ])
    func accepts(input: String, expected: String) {
        #expect(LinkValidator.validated(input)?.absoluteString == expected)
    }

    @Test(arguments: ["javascript:alert(1)", "file:///etc/passwd", "ftp://example.com", "smartnotes://x", "", "   ", "two words", "https://", "mailto:", "notadomain"])
    func rejects(input: String) {
        #expect(LinkValidator.validated(input) == nil)
    }
}

@Suite struct HTMLSanitizerTests {
    @Test func keepsFormattingTagsAndDropsAttributes() {
        let html = #"<p style="color:red" class="x"><b onclick="evil()">Bold</b> <i>it</i> <span style="background:url(https://track.er/x.png)">s</span></p>"#
        #expect(HTMLSanitizer.sanitize(html) == "<p><b>Bold</b> <i>it</i> <span>s</span></p>")
    }

    @Test func removesActiveAndEmbeddedContent() {
        let html = #"<head><title>T</title><style>p{}</style></head><script>alert(1)</script>Text<img src="https://x/y.png"><iframe src="https://x"></iframe><link rel="stylesheet" href="https://x.css">"#
        #expect(HTMLSanitizer.sanitize(html) == "Text")
    }

    @Test func keepsOnlySafeHrefs() {
        #expect(HTMLSanitizer.sanitize(#"<a href="https://example.com/?a=1&amp;b=2">x</a>"#) == #"<a href="https://example.com/?a=1&amp;b=2">x</a>"#)
        #expect(HTMLSanitizer.sanitize(#"<a href="javascript:alert(1)">x</a>"#) == "<a>x</a>")
        #expect(HTMLSanitizer.sanitize(#"<a href='mailto:a@b.co'>m</a>"#) == #"<a href="mailto:a@b.co">m</a>"#)
    }

    @Test func removesComments() {
        #expect(HTMLSanitizer.sanitize("a<!-- <script>x</script> -->b") == "ab")
    }
}

@Suite struct BlockCommandTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func note(_ specs: [(BlockType, String)]) -> Note {
        let ranks = Rank.evenlySpaced(specs.count)
        return Note(createdAt: now, manualRank: "i", blocks: zip(specs, ranks).map {
            NoteBlock(type: $0.0, rank: $1, content: RichText(plain: $0.1))
        })
    }

    @Test func setTypeClearsIncompatibleState() throws {
        var n = note([(.checklistItem, "a")])
        n.blocks[0].isChecked = true
        n.blocks[0].indentLevel = 2
        let asBullet = try #require(BlockEditing.setType(n, blockID: n.blocks[0].id, to: .bulletItem))
        #expect(!asBullet.blocks[0].isChecked && asBullet.blocks[0].indentLevel == 2)
        let asHeading = try #require(BlockEditing.setType(asBullet, blockID: n.blocks[0].id, to: .heading2))
        #expect(asHeading.blocks[0].indentLevel == 0)
        #expect(BlockEditing.setType(asHeading, blockID: n.blocks[0].id, to: .heading2) == nil)
    }

    @Test func indentOnlyListsAndClamps() {
        let n = note([(.paragraph, "p"), (.bulletItem, "b")])
        #expect(BlockEditing.indent(n, blockID: n.blocks[0].id, by: 1) == nil)
        #expect(BlockEditing.indent(n, blockID: n.blocks[1].id, by: -1) == nil)
        var current = n
        for _ in 0..<10 { current = BlockEditing.indent(current, blockID: n.blocks[1].id, by: 1) ?? current }
        #expect(current.blocks[1].indentLevel == NoteBlock.maxIndentLevel)
    }

    @Test func moveUpDownPreservesContent() throws {
        var n = note([(.paragraph, "a"), (.checklistItem, "b"), (.paragraph, "c")])
        n.blocks[1].isChecked = true
        n.blocks[1].content = RichText(runs: [TextRun("b", marks: [.bold])])
        let moved = try #require(BlockEditing.move(n, blockID: n.blocks[1].id, by: -1))
        #expect(moved.blocks.map(\.content.plainText) == ["b", "a", "c"])
        #expect(moved.blocks[0].isChecked && moved.blocks[0].content.runs[0].marks == [.bold])
        #expect(BlockEditing.move(moved, blockID: moved.blocks[0].id, by: -1) == nil) // already first
        let down = try #require(BlockEditing.move(moved, blockID: moved.blocks[0].id, by: 2))
        #expect(down.blocks.map(\.content.plainText) == ["a", "c", "b"])
    }

    @Test func dragMoveBeforeAndAfter() throws {
        let n = note([(.paragraph, "a"), (.paragraph, "b"), (.paragraph, "c"), (.paragraph, "d")])
        let id = { (i: Int) in n.blocks[i].id }
        #expect(try #require(BlockEditing.move(n, blockID: id(3), relativeTo: id(0), placeAfter: false)).blocks.map(\.content.plainText) == ["d", "a", "b", "c"])
        #expect(try #require(BlockEditing.move(n, blockID: id(0), relativeTo: id(2), placeAfter: true)).blocks.map(\.content.plainText) == ["b", "c", "a", "d"])
        #expect(BlockEditing.move(n, blockID: id(1), relativeTo: id(0), placeAfter: true) == nil) // same place
        #expect(BlockEditing.move(n, blockID: id(1), relativeTo: id(1), placeAfter: true) == nil)
    }

    @Test func moveRenumbersDuplicateRanks() throws {
        var n = note([(.paragraph, "a"), (.paragraph, "b"), (.paragraph, "c")])
        for i in n.blocks.indices { n.blocks[i].rank = "i" }
        let ids = n.blocks.map(\.id)
        let moved = try #require(BlockEditing.move(n, blockID: ids[2], relativeTo: ids[0], placeAfter: false))
        #expect(moved.blocks.first?.id == ids[2])
        #expect(Set(moved.blocks.map(\.rank)).count == 3)
    }

    @Test func pasteSingleParagraphInline() throws {
        let n = note([(.paragraph, "Hello world")])
        let result = try #require(try BlockEditing.paste(n, blockID: n.blocks[0].id, range: 6..<11,
            paragraphs: [PastedParagraph(content: RichText(runs: [TextRun("there", marks: [.bold])]))]))
        #expect(result.note.blocks[0].content.runs == [TextRun("Hello "), TextRun("there", marks: [.bold])])
        #expect(result.focusOffset == 11)
    }

    @Test func pasteMultipleParagraphsSplitsBlock() throws {
        let n = note([(.paragraph, "Start|End"), (.paragraph, "next")])
        let result = try #require(try BlockEditing.paste(n, blockID: n.blocks[0].id, range: 6..<6, paragraphs: [
            PastedParagraph(content: RichText(plain: "one")),
            PastedParagraph(type: .bulletItem, content: RichText(plain: "two")),
            PastedParagraph(content: RichText(plain: "three")),
        ]))
        #expect(result.note.blocks.map(\.content.plainText) == ["Start|one", "two", "threeEnd", "next"])
        #expect(result.note.blocks.map(\.type) == [.paragraph, .bulletItem, .paragraph, .paragraph])
        #expect(result.focusBlockID == result.note.blocks[2].id && result.focusOffset == 5)
    }

    @Test func pasteListIntoEmptyBlockAdoptsListType() throws {
        let n = note([(.paragraph, "")])
        let result = try #require(try BlockEditing.paste(n, blockID: n.blocks[0].id, range: 0..<0, paragraphs: [
            PastedParagraph(type: .numberedItem, content: RichText(plain: "a")),
            PastedParagraph(type: .numberedItem, content: RichText(plain: "b")),
        ]))
        #expect(result.note.blocks.map(\.type) == [.numberedItem, .numberedItem])
    }

    @Test func rankNormalization() {
        var n = note([(.paragraph, "a"), (.paragraph, "b")])
        n.blocks[1].rank = "i" + String(repeating: "1", count: 30)
        let normalized = BlockEditing.normalizingRanks(n)
        #expect(normalized.blocks.allSatisfy { $0.rank.count < 5 })
        #expect(normalized.blocks.map(\.content.plainText) == ["a", "b"])
        let short = note([(.paragraph, "x")])
        #expect(BlockEditing.normalizingRanks(short) == short) // short ranks are left alone
    }
}

@MainActor
@Suite struct PasteConverterTests {
    private let template = TextRun("", marks: [.italic])

    @Test func plainTextSplitsLinesAndUsesTemplate() {
        let paragraphs = PasteConverter.plainParagraphs("one\r\ntwo\n\nfour\n", template: template)
        #expect(paragraphs.map(\.content.plainText) == ["one", "two", "", "four"])
        #expect(paragraphs[0].content.runs[0].marks == [.italic])
    }

    @Test func rtfMapsMarksAndLinksAndDropsUnsafeLinks() throws {
        let source = NSMutableAttributedString()
        source.append(NSAttributedString(string: "Bold", attributes: [.font: NSFont.boldSystemFont(ofSize: 30)]))
        source.append(NSAttributedString(string: " under", attributes: [.underlineStyle: NSUnderlineStyle.single.rawValue, .font: NSFont.systemFont(ofSize: 12)]))
        source.append(NSAttributedString(string: " site", attributes: [.link: URL(string: "https://example.com")!, .font: NSFont.systemFont(ofSize: 12)]))
        source.append(NSAttributedString(string: " bad\nSecond", attributes: [.link: URL(string: "javascript:alert(1)")!, .font: NSFont.systemFont(ofSize: 12)]))
        let data = try #require(source.rtf(from: NSRange(location: 0, length: source.length)))
        let board = NSPasteboard(name: .init("SmartNotesTests-\(UUID().uuidString)"))
        board.clearContents()
        board.setData(data, forType: .rtf)

        let paragraphs = try #require(PasteConverter.paragraphs(from: board, plainOnly: false, template: template))
        #expect(paragraphs.map(\.content.plainText) == ["Bold under site bad", "Second"])
        let runs = paragraphs[0].content.runs
        #expect(runs[0] == TextRun("Bold", marks: [.bold]))
        #expect(runs[1] == TextRun(" under", marks: [.underline]))
        #expect(runs[2] == TextRun(" site", link: URL(string: "https://example.com")))
        #expect(runs[3].link == nil) // unsafe link dropped, text kept
        board.releaseGlobally()
    }

    @Test func htmlListsBecomeListBlocks() throws {
        let board = NSPasteboard(name: .init("SmartNotesTests-\(UUID().uuidString)"))
        board.clearContents()
        board.setString("<ul><li><b>Milk</b></li><li>Eggs</li></ul><ol><li>First</li></ol><p>After <img src=\"https://example.com/t.png\"></p>", forType: .html)
        let paragraphs = try #require(PasteConverter.paragraphs(from: board, plainOnly: false, template: template))
        #expect(paragraphs.map(\.type) == [.bulletItem, .bulletItem, .numberedItem, .paragraph])
        #expect(paragraphs.map { $0.content.plainText.trimmingCharacters(in: .whitespaces) } == ["Milk", "Eggs", "First", "After"])
        #expect(paragraphs[0].content.runs.first?.marks.contains(.bold) == true)
        board.releaseGlobally()
    }

    @Test func plainOnlyIgnoresRichData() throws {
        let board = NSPasteboard(name: .init("SmartNotesTests-\(UUID().uuidString)"))
        board.clearContents()
        board.declareTypes([.html, .string], owner: nil)
        board.setString("<b>x</b>", forType: .html)
        board.setString("x", forType: .string)
        let paragraphs = try #require(PasteConverter.paragraphs(from: board, plainOnly: true, template: template))
        #expect(paragraphs[0].content.runs == [TextRun("x", marks: [.italic])])
        board.releaseGlobally()
    }
}

import AppKit
import Foundation
import Testing
@testable import SmartNotesKit

@Suite struct MarkdownImportTests {
    private func runs(_ text: String) -> [TextRun] {
        MarkdownImport.inline(text).runs
    }

    @Test func boldItalicStrikeAndCode() {
        #expect(runs("a **bold** b") == [TextRun("a "), TextRun("bold", marks: [.bold]), TextRun(" b")])
        #expect(runs("__bold__ and _it_") == [TextRun("bold", marks: [.bold]), TextRun(" and "), TextRun("it", marks: [.italic])])
        #expect(runs("*it* ~~gone~~") == [TextRun("it", marks: [.italic]), TextRun(" "), TextRun("gone", marks: [.strikethrough])])
        #expect(runs("***both***") == [TextRun("both", marks: [.bold, .italic])])
        #expect(runs("run `**not bold**` now") == [TextRun("run "), TextRun("**not bold**", marks: [.code]), TextRun(" now")])
    }

    @Test func nestedEmphasis() {
        #expect(runs("**bold *and it* bold**") == [
            TextRun("bold ", marks: [.bold]), TextRun("and it", marks: [.bold, .italic]), TextRun(" bold", marks: [.bold]),
        ])
    }

    @Test func literalSymbolsStayLiteral() {
        #expect(runs("2 * 3 * 4").map(\.text) == ["2 * 3 * 4"])
        #expect(runs("snake_case_name") == [TextRun("snake_case_name")])
        #expect(runs("**unclosed") == [TextRun("**unclosed")])
        #expect(runs("price: 5 ** 2") == [TextRun("price: 5 ** 2")])
    }

    @Test func escapesAndEntities() {
        #expect(runs("\\*not italic\\*") == [TextRun("*not italic*")])
        #expect(runs("Tom &amp; Jerry &lt;3 &#8364; &#x1F600;") == [TextRun("Tom & Jerry <3 € 😀")])
        #expect(runs("AT&T; & co") == [TextRun("AT&T; & co")])
    }

    @Test func linksKeepOnlySafeURLs() {
        #expect(runs("see [the **site**](https://example.com \"Title\")") == [
            TextRun("see "),
            TextRun("the ", link: URL(string: "https://example.com")),
            TextRun("site", marks: [.bold], link: URL(string: "https://example.com")),
        ])
        #expect(runs("[click](javascript:alert(1))") == [TextRun("click")])
        #expect(runs("<https://example.com> or <me@example.com>") == [
            TextRun("https://example.com", link: URL(string: "https://example.com")),
            TextRun(" or "),
            TextRun("me@example.com", link: URL(string: "mailto:me@example.com")),
        ])
        #expect(runs("![logo](https://example.com/a.png)") == [TextRun("logo")])
        #expect(runs("[not a link] (x)") == [TextRun("[not a link] (x)")])
    }

    @Test func blocksFromLines() {
        let text = """
        # Title
        ## Section ##
        Intro with **bold**.

        - one
          - nested *it*
        * [ ] todo
        - [x] done
        1. first
        2) second
        > quoted
        ---
        """
        let paragraphs = MarkdownImport.paragraphs(text)
        #expect(paragraphs.map(\.type) == [
            .heading1, .heading2, .paragraph, .paragraph, .bulletItem, .bulletItem, .checklistItem, .checklistItem,
            .numberedItem, .numberedItem, .quote,
        ])
        #expect(paragraphs.map(\.content.plainText) == [
            "Title", "Section", "Intro with bold.", "", "one", "nested it", "todo", "done", "first", "second", "quoted",
        ])
        #expect(paragraphs.map(\.indentLevel) == [0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0])
        #expect(paragraphs.map(\.isChecked) == [false, false, false, false, false, false, false, true, false, false, false])
        #expect(paragraphs[2].content.runs[1] == TextRun("bold", marks: [.bold]))
    }

    @Test func fencedCodeStaysLiteral() {
        let paragraphs = MarkdownImport.paragraphs("```swift\nlet a = **b**\n```\nafter")
        #expect(paragraphs.map(\.content.plainText) == ["let a = **b**", "after"])
        #expect(paragraphs[0].content.runs[0].marks == [.code])
    }

    @Test func templateFormattingIsKept() {
        let template = TextRun("", marks: [.underline], fontFamily: .serif, fontSize: .large)
        let paragraphs = MarkdownImport.paragraphs("a **b**", template: template)
        #expect(paragraphs[0].content.runs == [
            TextRun("a ", marks: [.underline], fontFamily: .serif, fontSize: .large),
            TextRun("b", marks: [.underline, .bold], fontFamily: .serif, fontSize: .large),
        ])
    }

    @Test func detectsMarkdown() {
        #expect(MarkdownImport.looksLikeMarkdown("Hello **world**"))
        #expect(MarkdownImport.looksLikeMarkdown("intro\n- item"))
        #expect(MarkdownImport.looksLikeMarkdown("Tom &amp; Jerry"))
        #expect(!MarkdownImport.looksLikeMarkdown("Just a sentence, 2 * 3."))
    }
}

@MainActor
@Suite struct MarkdownPasteTests {
    private let template = TextRun("")

    private func board() -> NSPasteboard {
        let board = NSPasteboard(name: .init("SmartNotesTests-\(UUID().uuidString)"))
        board.clearContents()
        return board
    }

    @Test func plainMarkdownIsConverted() throws {
        let board = board()
        board.setString("Ciao **Marco**,\n- punto", forType: .string)
        let paragraphs = try #require(PasteConverter.paragraphs(from: board, plainOnly: false, template: template))
        #expect(paragraphs[0].content.runs == [TextRun("Ciao "), TextRun("Marco", marks: [.bold]), TextRun(",")])
        #expect(paragraphs[1].type == .bulletItem)
        board.releaseGlobally()
    }

    @Test func pasteAndMatchStyleKeepsSymbols() throws {
        let board = board()
        board.setString("**x**", forType: .string)
        let paragraphs = try #require(PasteConverter.paragraphs(from: board, plainOnly: true, template: template))
        #expect(paragraphs[0].content.plainText == "**x**")
        board.releaseGlobally()
    }

    /// Code editors put Markdown source as HTML with only colours: the Markdown wins.
    @Test func unformattedRichDataFallsBackToMarkdown() throws {
        let board = board()
        board.declareTypes([.html, .string], owner: nil)
        board.setString("<div><span style=\"color:#c00\">**Bold** text</span></div>", forType: .html)
        board.setString("**Bold** text", forType: .string)
        let paragraphs = try #require(PasteConverter.paragraphs(from: board, plainOnly: false, template: template))
        #expect(paragraphs.map(\.content.runs) == [[TextRun("Bold", marks: [.bold]), TextRun(" text")]])
        board.releaseGlobally()
    }

    @Test func formattedRichDataIsKept() throws {
        let board = board()
        board.declareTypes([.html, .string], owner: nil)
        board.setString("<p><b>Real</b> and **literal**</p>", forType: .html)
        board.setString("Real and **literal**", forType: .string)
        let paragraphs = try #require(PasteConverter.paragraphs(from: board, plainOnly: false, template: template))
        #expect(paragraphs[0].content.plainText.contains("**literal**"))
        #expect(paragraphs[0].content.runs.first?.marks == [.bold])
        board.releaseGlobally()
    }
}

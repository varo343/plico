import Foundation
import Testing
@testable import SmartNotesKit

@Suite struct SlashCommandTests {
    @Test func matchingRanksNamesBeforeAliases() {
        #expect(SlashCommand.matches("").count == SlashCommand.all.count)
        #expect(SlashCommand.matches("che").map(\.name) == ["checkbox"])
        #expect(SlashCommand.matches("CHECK").first?.name == "checkbox")
        #expect(SlashCommand.matches("todo").map(\.name) == ["checkbox"])
        #expect(SlashCommand.matches("h").map(\.name).prefix(3) == ["h1", "h2", "h3"])
        #expect(SlashCommand.matches("b").first?.name == "bullet")
        #expect(SlashCommand.matches("zzz").isEmpty)
        #expect(SlashCommand.exact("list")?.type == .bulletItem)
        #expect(SlashCommand.exact("bul") == nil)
    }

    @Test(arguments: [
        ("/", 1, "", 0..<1),
        ("/che", 4, "che", 0..<4),
        ("Buy milk /bul", 13, "bul", 9..<13),
        ("line\n/h", 7, "h", 5..<7),
        ("/che", 2, "c", 0..<2),      // caret mid-word: the token ends at the caret
    ])
    func detectsTokens(text: String, caret: Int, query: String, range: Range<Int>) {
        #expect(SlashTrigger.token(in: text, caret: caret) == SlashTrigger.Token(range: range, query: query))
    }

    @Test(arguments: [
        ("https://example.com", 8),   // URL: "/" after ":"
        ("1/2", 3),                   // fraction
        ("/che ck", 7),               // space ends the token
        ("plain", 5),
        ("", 0),
    ])
    func ignoresNonTokens(text: String, caret: Int) {
        #expect(SlashTrigger.token(in: text, caret: caret) == nil)
    }

    @Test func completedCommandNeedsExactNameAndSpace() {
        #expect(SlashTrigger.completedCommand(in: "/checkbox ", caret: 10)?.0.type == .checklistItem)
        #expect(SlashTrigger.completedCommand(in: "/checkbox ", caret: 10)?.1 == 0..<10)
        #expect(SlashTrigger.completedCommand(in: "Note /bullet ", caret: 13)?.1 == 5..<13)
        #expect(SlashTrigger.completedCommand(in: "/check", caret: 6) == nil)      // no space yet
        #expect(SlashTrigger.completedCommand(in: "/checkb ", caret: 8) == nil)    // not exact
    }

    @Test func applyRemovesTypedTextAndChangesType() throws {
        let block = NoteBlock(rank: "i", content: RichText(runs: [TextRun("Buy ", marks: [.bold]), TextRun("/checkbox")]))
        let note = Note(createdAt: .now, manualRank: "i", blocks: [block])
        let result = try BlockEditing.applySlashCommand(note, blockID: block.id, removing: 4..<13, type: .checklistItem)
        #expect(result.note.blocks[0].type == .checklistItem)
        #expect(result.note.blocks[0].content.runs == [TextRun("Buy ", marks: [.bold])])
        #expect(result.focusOffset == 4)
    }
}

import Foundation
import Testing
@testable import SmartNotesKit

@Suite struct NestedTextEditingTests {
    private func note(_ blocks: [NoteBlock]) -> Note {
        Note(createdAt: Date(timeIntervalSince1970: 0), manualRank: "i", blocks: blocks)
    }

    @Test func mergingBlocksKeepsBothNestedTexts() throws {
        let n = note([
            NoteBlock(rank: "a", content: RichText(plain: "One"), detail: RichText(plain: "first")),
            NoteBlock(rank: "b", content: RichText(plain: "Two"), detail: RichText(plain: "second")),
        ])
        let result = try #require(try BlockEditing.mergeWithPrevious(n, blockID: n.blocks[1].id))
        #expect(result.note.blocks.map(\.detail.plainText) == ["first\nsecond"])
    }

    @Test func splittingLeavesNestedTextOnTheOriginalBlock() throws {
        let n = note([NoteBlock(rank: "a", content: RichText(plain: "OneTwo"), detail: RichText(plain: "kept"))])
        let result = try BlockEditing.split(n, blockID: n.blocks[0].id, atUTF16Offset: 3)
        #expect(result.note.blocks.map(\.detail.plainText) == ["kept", ""])
    }

    @Test func deletingAcrossBlocksKeepsTheLastBlocksNestedText() throws {
        let n = note([
            NoteBlock(rank: "a", content: RichText(plain: "One")),
            NoteBlock(rank: "b", content: RichText(plain: "Two"), detail: RichText(plain: "email")),
        ])
        let selection = BlockRangeSelection(anchor: BlockPosition(blockID: n.blocks[0].id, offset: 1),
                                            focus: BlockPosition(blockID: n.blocks[1].id, offset: 1))
        let result = try BlockEditing.deleteRange(n, selection: selection)
        #expect(result.note.blocks.map(\.content.plainText) == ["Owo"])
        #expect(result.note.blocks[0].detail.plainText == "email")
    }

    @Test func copyAndPasteCarryNestedText() throws {
        let n = note([
            NoteBlock(rank: "a", content: RichText(plain: "One"), detail: RichText(plain: "hidden")),
            NoteBlock(rank: "b", content: RichText(plain: "Two")),
        ])
        let selection = BlockRangeSelection(anchor: BlockPosition(blockID: n.blocks[0].id, offset: 0),
                                            focus: BlockPosition(blockID: n.blocks[1].id, offset: 3))
        let copied = BlockEditing.copiedParagraphs(n, selection: selection)
        #expect(copied.map(\.detail) == [RichText(plain: "hidden"), nil])

        let target = note([NoteBlock(rank: "a"), NoteBlock(rank: "b", content: RichText(plain: "x"))])
        let pasted = try #require(try BlockEditing.paste(target, blockID: target.blocks[1].id, range: 1..<1, paragraphs: copied))
        #expect(pasted.note.blocks.map(\.detail.plainText) == ["", "hidden", ""])
    }

    @Test func pasteboardDataWithoutNestedTextStillDecodes() throws {
        let json = #"[{"content":{"runs":[{"text":"a"}],"version":1},"indentLevel":0,"isChecked":false,"type":"paragraph"}]"#
        let paragraphs = try JSONDecoder().decode([PastedParagraph].self, from: Data(json.utf8))
        #expect(paragraphs == [PastedParagraph(content: RichText(plain: "a"))])
    }

    @Test func pastedParagraphsFlattenToReadableLines() {
        let text = BlockEditing.nestedText(from: [
            PastedParagraph(content: RichText(runs: [TextRun("Hi "), TextRun("all", marks: [.bold])])),
            PastedParagraph(type: .bulletItem, content: RichText(plain: "a")),
            PastedParagraph(type: .bulletItem, content: RichText(plain: "b"), indentLevel: 1),
            PastedParagraph(type: .numberedItem, content: RichText(plain: "c")),
            PastedParagraph(type: .numberedItem, content: RichText(plain: "d")),
            PastedParagraph(type: .checklistItem, content: RichText(plain: "e"), isChecked: true, detail: RichText(plain: "more")),
        ])
        #expect(text.plainText == "Hi all\n• a\n    • b\n1. c\n2. d\n☑ e\n    more")
        #expect(text.runs[1] == TextRun("all", marks: [.bold]))
    }

    @Test func nestedTextIsSearchable() {
        let blocks = [NoteBlock(rank: "a", content: RichText(plain: "Email"), detail: RichText(plain: "Campagna Natale"))]
        #expect(NoteText.searchText(title: "", blocks: blocks).contains("campagna natale"))
    }

    @Test func detailTypingCoalescesSeparatelyFromMainText() {
        var history = EditHistory()
        let id = UUID()
        let start = Date(timeIntervalSince1970: 0)
        let snapshot = EditHistory.Snapshot(blocks: [], caret: nil)
        history.record(before: snapshot, kind: .typing(blockID: id), at: start)
        history.record(before: snapshot, kind: .typingDetail(blockID: id), at: start.addingTimeInterval(0.1))
        history.record(before: snapshot, kind: .typingDetail(blockID: id), at: start.addingTimeInterval(0.2))
        #expect(history.undoStack.count == 2)
    }
}

@Suite struct NestedTextExportTests {
    private let note = Note(createdAt: Date(timeIntervalSince1970: 0), manualRank: "i", blocks: [
        NoteBlock(type: .checklistItem, rank: "a", content: RichText(plain: "Write email"),
                  detail: RichText(runs: [TextRun("Hi "), TextRun("team", marks: [.bold]), TextRun("\nThanks")])),
        NoteBlock(rank: "b", content: RichText(plain: "Plain")),
    ])

    @Test func markdownShowsNestedTextAsAQuoteUnderTheItem() {
        let markdown = NoteExport.markdown(note)
        #expect(markdown.contains("- [ ] Write email\n  > Hi **team**  \n  > Thanks\n"))
    }

    @Test func jsonKeepsNestedTextAndOmitsItWhenEmpty() throws {
        let data = try NoteExport.json([note], exportedAt: Date(timeIntervalSince1970: 0))
        let document = try {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(NoteExport.Document.self, from: data)
        }()
        #expect(document.notes[0].blocks.map(\.detail) == [note.blocks[0].detail, nil])
    }
}

@Suite struct NestBlockTests {
    private func note(_ blocks: [NoteBlock]) -> Note {
        Note(createdAt: Date(timeIntervalSince1970: 0), manualRank: "i", blocks: blocks)
    }

    @Test func droppedBlockBecomesTheLastLineOfNestedText() throws {
        let n = note([
            NoteBlock(type: .checklistItem, rank: "a", content: RichText(plain: "Email marketing"), detail: RichText(plain: "Oggetto")),
            NoteBlock(rank: "b", content: RichText(runs: [TextRun("Ciao "), TextRun("team", marks: [.bold])])),
            NoteBlock(rank: "c", content: RichText(plain: "Altro")),
        ])
        let result = try #require(BlockEditing.nest(n, blockID: n.blocks[1].id, into: n.blocks[0].id))
        #expect(result.blocks.map(\.content.plainText) == ["Email marketing", "Altro"])
        #expect(result.blocks[0].detail.plainText == "Oggetto\nCiao team")
        #expect(result.blocks[0].detail.runs.contains(TextRun("team", marks: [.bold])))
    }

    @Test func listMarkerTagAndNestedTextComeAlong() throws {
        let n = note([
            NoteBlock(rank: "a", content: RichText(plain: "Parent")),
            NoteBlock(type: .checklistItem, rank: "b", content: RichText(plain: "Call"), isChecked: true, indentLevel: 2,
                      tag: .priority(.high), detail: RichText(plain: "number")),
        ])
        let result = try #require(BlockEditing.nest(n, blockID: n.blocks[1].id, into: n.blocks[0].id))
        #expect(result.blocks.count == 1)
        #expect(result.blocks[0].detail.plainText == "☑ Call [High]\n    number")
    }

    @Test func nestingIntoItselfDoesNothing() {
        let n = note([NoteBlock(rank: "a", content: RichText(plain: "One"))])
        #expect(BlockEditing.nest(n, blockID: n.blocks[0].id, into: n.blocks[0].id) == nil)
    }
}

@Suite struct NestedRowsTests {
    private func note(_ blocks: [NoteBlock]) -> Note {
        Note(createdAt: Date(timeIntervalSince1970: 0), manualRank: "i", blocks: blocks)
    }

    private func rows(_ text: String) -> [String] {
        let detail = RichText(plain: text)
        return BlockEditing.nestedRows(in: detail).map { detail.slice($0).plainText }
    }

    @Test func rowsKeepTheirIndentedLinesAndSkipBlankOnes() {
        #expect(rows("☑ Call [High]\n    number\n\nCiao\n\n   \nSaluti") == ["☑ Call [High]\n    number", "Ciao", "Saluti"])
        #expect(rows("") == [])
        #expect(rows("one\n  two\n\n  three\nfour") == ["one\n  two\n\n  three", "four"])
    }

    @Test func rowReadsBackAsTheBlockItCameFrom() throws {
        let n = note([
            NoteBlock(rank: "a", content: RichText(plain: "Parent")),
            NoteBlock(type: .checklistItem, rank: "b", content: RichText(runs: [TextRun("Call "), TextRun("Anna", marks: [.bold])]),
                      isChecked: true, tag: .custom("Design"), detail: RichText(plain: "number\n  ext 4")),
        ])
        let original = n.blocks[1]
        let nested = try #require(BlockEditing.nest(n, blockID: original.id, into: n.blocks[0].id))
        let row = try #require(BlockEditing.nestedRows(in: nested.blocks[0].detail).first)
        let result = try #require(BlockEditing.unnest(nested, blockID: nested.blocks[0].id, row: row, relativeTo: nested.blocks[0].id, placeAfter: true))

        #expect(result.note.blocks.count == 2)
        #expect(result.note.blocks[0].detail.isEmpty)
        let back = result.note.blocks[1]
        #expect(back.type == .checklistItem && back.isChecked && back.tag == .custom("Design"))
        #expect(back.content == original.content)
        #expect(back.detail.plainText == "number\n  ext 4")
        #expect(result.focusBlockID == back.id && result.focusOffset == 9)
    }

    @Test func markersGiveTheKind() {
        func read(_ text: String) -> PastedParagraph { BlockEditing.paragraph(fromNestedRow: RichText(plain: text)) }
        #expect(read("• item").type == .bulletItem)
        #expect(read("- item").type == .bulletItem)
        #expect(read("12. item").type == .numberedItem)
        #expect(read("☐ todo").type == .checklistItem && !read("☐ todo").isChecked)
        #expect(read("        • deep").indentLevel == 2)
        #expect(read("    plain").indentLevel == 0)
        #expect(read("Just text").content.plainText == "Just text")
        #expect(read("see [docs]").tag == .custom("docs"))
        #expect(read("[High]").tag == nil) // Nothing would be left of the row.
        #expect(read("2 * 3").type == .paragraph)
    }

    @Test func unnestPlacesTheRowWhereItWasDropped() throws {
        let n = note([
            NoteBlock(rank: "a", content: RichText(plain: "First"), detail: RichText(plain: "Ciao\n\nSaluti")),
            NoteBlock(rank: "b", content: RichText(plain: "Second")),
        ])
        let rows = BlockEditing.nestedRows(in: n.blocks[0].detail)
        let result = try #require(BlockEditing.unnest(n, blockID: n.blocks[0].id, row: rows[1], relativeTo: n.blocks[1].id, placeAfter: true))
        #expect(result.note.blocks.map(\.content.plainText) == ["First", "Second", "Saluti"])
        #expect(result.note.blocks[0].detail.plainText == "Ciao\n")
        let before = try #require(BlockEditing.unnest(n, blockID: n.blocks[0].id, row: rows[0], relativeTo: n.blocks[0].id, placeAfter: false))
        #expect(before.note.blocks.map(\.content.plainText) == ["Ciao", "First", "Second"])
        #expect(before.note.blocks[1].detail.plainText == "\nSaluti")
    }

    @Test func rowMovesIntoAnotherRow() throws {
        let n = note([
            NoteBlock(rank: "a", content: RichText(plain: "From"), detail: RichText(plain: "keep\n• move [Low]")),
            NoteBlock(rank: "b", content: RichText(plain: "To"), detail: RichText(plain: "there")),
        ])
        let row = BlockEditing.nestedRows(in: n.blocks[0].detail)[1]
        let result = try #require(BlockEditing.moveNestedRow(n, blockID: n.blocks[0].id, row: row, into: n.blocks[1].id))
        #expect(result.blocks.map(\.detail.plainText) == ["keep", "there\n• move [Low]"])
        #expect(BlockEditing.moveNestedRow(n, blockID: n.blocks[0].id, row: row, into: n.blocks[0].id) == nil)
        #expect(BlockEditing.moveNestedRow(n, blockID: n.blocks[0].id, row: 0..<99, into: n.blocks[1].id) == nil)
    }
}

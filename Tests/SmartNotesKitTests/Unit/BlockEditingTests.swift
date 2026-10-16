import Foundation
import Testing
@testable import SmartNotesKit

@Suite struct BlockEditingTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func note(_ blocks: [(BlockType, RichText)]) -> Note {
        let ranks = Rank.evenlySpaced(blocks.count)
        return Note(createdAt: now, manualRank: "i", blocks: zip(blocks, ranks).map {
            NoteBlock(type: $0.0, rank: $1, content: $0.1, isChecked: $0.0 == .checklistItem)
        })
    }

    // MARK: RichText split / join

    @Test func splitKeepsFormattingOnBothSides() {
        let text = RichText(runs: [TextRun("Hello ", marks: [.bold]), TextRun("world", marks: [.italic])])
        let (head, tail) = text.split(atUTF16Offset: 3)
        #expect(head.runs == [TextRun("Hel", marks: [.bold])])
        #expect(tail.runs == [TextRun("lo ", marks: [.bold]), TextRun("world", marks: [.italic])])
        #expect(head + tail == text)
    }

    @Test(arguments: [-5, 0, 11, 99])
    func splitClampsAtEdges(offset: Int) {
        let text = RichText(plain: "Hello world")
        let (head, tail) = text.split(atUTF16Offset: offset)
        #expect(head + tail == text)
    }

    @Test func splitNeverBreaksComposedCharacters() {
        let text = RichText(plain: "a👍🏽b") // 👍🏽 is 4 UTF-16 units
        let (head, tail) = text.split(atUTF16Offset: 2) // inside the emoji
        #expect(head.plainText == "a")
        #expect(tail.plainText == "👍🏽b")
    }

    @Test func joinMergesMatchingRuns() {
        let joined = RichText(runs: [TextRun("ab", marks: [.bold])]) + RichText(runs: [TextRun("cd", marks: [.bold])])
        #expect(joined.runs == [TextRun("abcd", marks: [.bold])])
    }

    // MARK: Enter

    @Test func enterSplitsParagraphAtCaret() throws {
        let n = note([(.paragraph, RichText(runs: [TextRun("Hello", marks: [.bold]), TextRun(" world")]))])
        let result = try BlockEditing.split(n, blockID: n.blocks[0].id, atUTF16Offset: 5)
        #expect(result.note.blocks.map(\.content.plainText) == ["Hello", " world"])
        #expect(result.note.blocks[0].content.runs == [TextRun("Hello", marks: [.bold])])
        #expect(result.focusBlockID == result.note.blocks[1].id)
        #expect(result.focusOffset == 0)
    }

    @Test func enterInHeadingContinuesAsParagraph() throws {
        let n = note([(.heading1, RichText(plain: "Title")), (.paragraph, RichText(plain: "next"))])
        let result = try BlockEditing.split(n, blockID: n.blocks[0].id, atUTF16Offset: 5)
        #expect(result.note.blocks.map(\.type) == [.heading1, .paragraph, .paragraph])
        #expect(result.note.blocks.map(\.content.plainText) == ["Title", "", "next"])
    }

    @Test func enterInChecklistContinuesUncheckedAtSameIndent() throws {
        var n = note([(.checklistItem, RichText(plain: "Buy milk"))])
        n.blocks[0].indentLevel = 2
        let result = try BlockEditing.split(n, blockID: n.blocks[0].id, atUTF16Offset: 8)
        let new = result.note.blocks[1]
        #expect(new.type == .checklistItem && !new.isChecked && new.indentLevel == 2)
        #expect(result.note.blocks[0].isChecked) // original keeps its state
    }

    @Test func enterOnEmptyListItemLeavesList() throws {
        let n = note([(.bulletItem, .empty)])
        let result = try BlockEditing.split(n, blockID: n.blocks[0].id, atUTF16Offset: 0)
        #expect(result.note.blocks.count == 1)
        #expect(result.note.blocks[0].type == .paragraph)
    }

    @Test func enterAtStartInsertsEmptyBlockAbove() throws {
        let n = note([(.paragraph, RichText(plain: "first")), (.heading2, RichText(plain: "Heading"))])
        let headingID = n.blocks[1].id
        let result = try BlockEditing.split(n, blockID: headingID, atUTF16Offset: 0)
        #expect(result.note.blocks.map(\.content.plainText) == ["first", "", "Heading"])
        #expect(result.note.blocks[2].type == .heading2)
        #expect(result.focusBlockID == headingID)
    }

    // MARK: Backspace

    @Test func backspaceMergesParagraphIntoPrevious() throws {
        let n = note([(.checklistItem, RichText(runs: [TextRun("Done", marks: [.bold])])), (.paragraph, RichText(plain: " later"))])
        let result = try #require(try BlockEditing.mergeWithPrevious(n, blockID: n.blocks[1].id))
        #expect(result.note.blocks.count == 1)
        let merged = result.note.blocks[0]
        #expect(merged.type == .checklistItem && merged.isChecked)
        #expect(merged.content.runs == [TextRun("Done", marks: [.bold]), TextRun(" later")])
        #expect(result.focusBlockID == merged.id && result.focusOffset == 4)
    }

    @Test func backspaceOnListItemConvertsToParagraphFirst() throws {
        let n = note([(.paragraph, RichText(plain: "a")), (.bulletItem, RichText(plain: "b"))])
        let result = try #require(try BlockEditing.mergeWithPrevious(n, blockID: n.blocks[1].id))
        #expect(result.note.blocks.map(\.type) == [.paragraph, .paragraph])
        #expect(result.note.blocks.map(\.content.plainText) == ["a", "b"])
    }

    @Test func backspaceOnFirstParagraphDoesNothing() throws {
        let n = note([(.paragraph, RichText(plain: "a"))])
        #expect(try BlockEditing.mergeWithPrevious(n, blockID: n.blocks[0].id) == nil)
    }

    @Test func repeatedEnterKeepsRanksOrdered() throws {
        var n = note([(.paragraph, RichText(plain: "x"))])
        var focus = n.blocks[0].id
        for i in 0..<200 {
            n.blocks[n.blocks.firstIndex { $0.id == focus }!].content = RichText(plain: "line \(i)")
            let result = try BlockEditing.split(n, blockID: focus, atUTF16Offset: 99)
            n = result.note
            focus = result.focusBlockID
        }
        #expect(n.blocks.count == 201)
        #expect(Set(n.blocks.map(\.rank)).count == 201)
        #expect(n.blocks.map(\.rank) == n.blocks.map(\.rank).sorted())
        #expect(n.blocks.prefix(3).map(\.content.plainText) == ["line 0", "line 1", "line 2"])
    }

    @Test func ensuringEditableBlock() {
        let empty = Note(createdAt: now, manualRank: "i")
        #expect(BlockEditing.ensuringEditableBlock(empty).blocks.count == 1)
        let full = note([(.paragraph, RichText(plain: "a"))])
        #expect(BlockEditing.ensuringEditableBlock(full) == full)
    }
}

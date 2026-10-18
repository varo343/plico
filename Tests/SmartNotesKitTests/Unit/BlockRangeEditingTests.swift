import Foundation
import Testing
@testable import SmartNotesKit

@Suite struct BlockRangeEditingTests {
    private func note(_ blocks: [(BlockType, String)]) -> Note {
        let ranks = Rank.evenlySpaced(blocks.count)
        return Note(createdAt: Date(timeIntervalSince1970: 0), manualRank: "i", blocks: zip(blocks, ranks).map {
            NoteBlock(type: $0.0, rank: $1, content: RichText(plain: $0.1))
        })
    }

    private func position(_ note: Note, _ index: Int, _ offset: Int) -> BlockPosition {
        BlockPosition(blockID: note.blocks[index].id, offset: offset)
    }

    @Test func segmentsAreInDocumentOrderWhicheverWayTheDragWent() {
        let n = note([(.paragraph, "Hello"), (.bulletItem, "middle"), (.checklistItem, "Task")])
        let down = BlockRangeSelection(anchor: position(n, 0, 2), focus: position(n, 2, 3))
        let up = BlockRangeSelection(anchor: position(n, 2, 3), focus: position(n, 0, 2))
        let expected = [
            BlockSegment(blockID: n.blocks[0].id, range: 2..<5),
            BlockSegment(blockID: n.blocks[1].id, range: 0..<6),
            BlockSegment(blockID: n.blocks[2].id, range: 0..<3),
        ]
        #expect(BlockEditing.segments(of: down, in: n) == expected)
        #expect(BlockEditing.segments(of: up, in: n) == expected)
    }

    @Test func deleteJoinsFirstAndLastBlockAndDropsTheMiddle() throws {
        let n = note([(.checklistItem, "Buy milk"), (.paragraph, "gone"), (.bulletItem, "and bread")])
        let selection = BlockRangeSelection(anchor: position(n, 2, 4), focus: position(n, 0, 4))
        let result = try BlockEditing.deleteRange(n, selection: selection)
        #expect(result.note.blocks.map(\.content.plainText) == ["Buy bread"])
        #expect(result.note.blocks[0].type == .checklistItem) // the first block keeps its kind
        #expect(result.focusBlockID == n.blocks[0].id)
        #expect(result.focusOffset == 4)
    }

    @Test func copyKeepsKindsAndRoundTripsThroughPaste() throws {
        var n = note([(.paragraph, "Intro"), (.bulletItem, "one"), (.checklistItem, "two")])
        n.blocks[1].indentLevel = 1
        n.blocks[2].isChecked = true
        let selection = BlockRangeSelection(anchor: position(n, 0, 2), focus: position(n, 2, 3))
        let copied = BlockEditing.copiedParagraphs(n, selection: selection)
        #expect(copied.map(\.content.plainText) == ["tro", "one", "two"])
        #expect(BlockEditing.plainText(of: copied) == "tro\n  - one\n- [x] two")

        let target = note([(.paragraph, "")])
        let pasted = try #require(try BlockEditing.paste(target, blockID: target.blocks[0].id, range: 0..<0, paragraphs: copied))
        #expect(pasted.note.blocks.map(\.type) == [.paragraph, .bulletItem, .checklistItem])
        #expect(pasted.note.blocks[1].indentLevel == 1)
        #expect(pasted.note.blocks[2].isChecked)
    }
}

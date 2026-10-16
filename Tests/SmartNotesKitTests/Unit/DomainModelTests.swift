import Foundation
import Testing
@testable import SmartNotesKit

@Suite struct DomainModelTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    @Test func blocksStaySortedByRank() {
        var note = Note(createdAt: now, manualRank: Rank.initial, blocks: [
            NoteBlock(rank: "r", content: RichText(plain: "second")),
            NoteBlock(rank: "i", content: RichText(plain: "first")),
        ])
        #expect(note.blocks.map(\.content.plainText) == ["first", "second"])
        note.blocks.append(NoteBlock(rank: "a", content: RichText(plain: "zeroth")))
        #expect(note.blocks.map(\.content.plainText) == ["zeroth", "first", "second"])
    }

    @Test func indentIsClamped() {
        var block = NoteBlock(type: .bulletItem, rank: "i", indentLevel: 99)
        #expect(block.indentLevel == NoteBlock.maxIndentLevel)
        block.indentLevel = -3
        #expect(block.indentLevel == 0)
    }

    @Test func duplicateHasFreshIdsAndSameContent() {
        let original = SampleData.notes(now: now)[0]
        let later = now.addingTimeInterval(60)
        let copy = original.duplicated(now: later, manualRank: "zz")
        #expect(copy.id != original.id)
        #expect(Set(copy.blocks.map(\.id)).isDisjoint(with: original.blocks.map(\.id)))
        #expect(copy.blocks.map(\.content) == original.blocks.map(\.content))
        #expect(copy.blocks.map(\.type) == original.blocks.map(\.type))
        #expect(copy.createdAt == later && copy.updatedAt == later)
        #expect(copy.title == original.title)
        #expect(copy.manualRank == "zz")
    }

    @Test func displayTitleFallsBackWithoutMutatingTitle() {
        let note = Note(createdAt: now, manualRank: "i", blocks: [
            NoteBlock(rank: "a", content: RichText(plain: "   ")),
            NoteBlock(rank: "b", content: RichText(plain: "  First line\nsecond")),
        ])
        #expect(note.displayTitle == "First line")
        #expect(note.title == "")
        #expect(Note(createdAt: now, manualRank: "i").displayTitle == "Untitled")
    }

    @Test func searchTextIsFoldedAndIncludesTitleAndBody() {
        let blocks = [NoteBlock(rank: "i", content: RichText(runs: [TextRun("Crème ", marks: [.bold]), TextRun("BRÛLÉE")]))]
        let text = NoteText.searchText(title: "Dessert Ideas", blocks: blocks)
        #expect(text.contains("dessert ideas"))
        #expect(text.contains("creme brulee"))
        #expect(NoteText.fold("CAFÉ") == "cafe")
    }

    @Test func previewCollapsesWhitespaceAndTruncates() {
        #expect(NoteText.preview(title: "T", body: "a\n\n  b\tc") == "a b c")
        #expect(NoteText.preview(title: "T", body: String(repeating: "x", count: 500)).count == NoteText.previewLength)
        // Untitled: first line becomes the display title, so the preview skips it.
        #expect(NoteText.preview(title: " ", body: "\nFirst\nSecond line") == "Second line")
    }

    @Test func externalItemKeyCannotCollideThroughSeparators() {
        let a = ExternalItemKey(provider: .outlook, accountId: "a|b", externalId: "c")
        let b = ExternalItemKey(provider: .outlook, accountId: "a", externalId: "b|c")
        #expect(a.storageKey != b.storageKey)
    }

    @Test func priorityOrdering() {
        #expect(Priority.allCases.sorted() == [.none, .low, .medium, .high])
    }
}

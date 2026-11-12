import Foundation
import Testing
@testable import SmartNotesKit

@Suite struct RowSortingTests {
    private func note(_ blocks: [NoteBlock]) -> Note {
        let ranks = Rank.evenlySpaced(blocks.count)
        return Note(createdAt: Date(timeIntervalSince1970: 0), manualRank: "i", blocks: zip(blocks, ranks).map { block, rank in
            var block = block
            block.rank = rank
            return block
        })
    }

    private func row(_ text: String, _ type: BlockType = .checklistItem, checked: Bool = false, tag: BlockTag? = nil, indent: Int = 0) -> NoteBlock {
        NoteBlock(type: type, rank: "a", content: RichText(plain: text), isChecked: checked, indentLevel: indent, tag: tag)
    }

    private func texts(_ note: Note?) -> [String] { note?.blocks.map(\.content.plainText) ?? [] }

    @Test func severityPutsHighFirstAndCompletedLast() {
        let n = note([
            row("none"), row("low", tag: .priority(.low)), row("done high", checked: true, tag: .priority(.high)),
            row("custom", tag: .custom("Design")), row("high", tag: .priority(.high)), row("medium", tag: .priority(.medium)),
            row("none 2"),
        ])
        #expect(texts(BlockEditing.sortRows(n, by: .severity)) == ["high", "medium", "low", "custom", "none", "none 2", "done high"])
    }

    @Test func reversedSeverityGoesLowToHighAndKeepsCompletedLast() {
        let n = note([
            row("none"), row("high", tag: .priority(.high)), row("done low", checked: true, tag: .priority(.low)),
            row("low", tag: .priority(.low)), row("custom", tag: .custom("Design")), row("medium", tag: .priority(.medium)),
        ])
        #expect(texts(BlockEditing.sortRows(n, by: .severity, reversed: true)) == ["none", "custom", "low", "medium", "high", "done low"])
    }

    @Test func reversedCompletionPutsCompletedFirst() {
        let n = note([row("a"), row("b done", checked: true), row("c"), row("d done", checked: true)])
        #expect(texts(BlockEditing.sortRows(n, by: .completion, reversed: true)) == ["b done", "d done", "a", "c"])
    }

    @Test func completionKeepsTheOrderOtherwise() {
        let n = note([row("a", checked: true), row("b"), row("c", checked: true), row("d")])
        #expect(texts(BlockEditing.sortRows(n, by: .completion)) == ["b", "d", "a", "c"])
        let sorted = BlockEditing.sortRows(n, by: .completion)!
        #expect(BlockEditing.sortRows(sorted, by: .completion) == nil) // already sorted
    }

    @Test func headingsAndTextStayAndSeparateLists() {
        let n = note([
            row("Intro", .paragraph),
            row("a done", checked: true), row("b"),
            row("Next", .heading2),
            row("c low", .bulletItem, tag: .priority(.low)), row("tagged text", .paragraph, tag: .priority(.high)),
        ])
        #expect(texts(BlockEditing.sortRows(n, by: .severity)) == ["Intro", "b", "a done", "Next", "tagged text", "c low"])
    }

    @Test func indentedRowsMoveWithTheirRowAndAreSortedToo() {
        let n = note([
            row("parent done", checked: true), row("child done", checked: true, indent: 1), row("child open", indent: 1),
            row("open"),
        ])
        #expect(texts(BlockEditing.sortRows(n, by: .completion)) == ["open", "parent done", "child open", "child done"])
    }

    @Test func selectionSortsOnlyThoseRows() {
        let n = note([row("x done", checked: true), row("y done", checked: true), row("z"), row("w")])
        let scope = Set(n.blocks[1...2].map(\.id))
        #expect(texts(BlockEditing.sortRows(n, by: .completion, within: scope)) == ["x done", "z", "y done", "w"])
        #expect(BlockEditing.sortRows(n, by: .completion, within: [n.blocks[0].id]) == nil)
    }

    @Test func checkingMovesBelowTheListAndUncheckingBringsItBack() throws {
        var n = note([row("a"), row("b"), row("c"), row("old", checked: true), row("After", .paragraph)])
        n.blocks[0].isChecked = true
        let checked = try #require(BlockEditing.settlingChecked(n, blockID: n.blocks[0].id))
        #expect(texts(checked) == ["b", "c", "old", "a", "After"])

        var unchecked = checked
        unchecked.blocks[3].isChecked = false
        let back = try #require(BlockEditing.settlingChecked(unchecked, blockID: unchecked.blocks[3].id))
        #expect(texts(back) == ["b", "c", "a", "old", "After"])
    }

    @Test func checkingAChildStaysUnderItsParent() throws {
        var n = note([row("p1"), row("c1", indent: 1), row("c2", indent: 1), row("p2")])
        n.blocks[1].isChecked = true
        #expect(texts(BlockEditing.settlingChecked(n, blockID: n.blocks[1].id)) == ["p1", "c2", "c1", "p2"])
        var parent = n
        parent.blocks[0].isChecked = true
        parent.blocks[1].isChecked = false
        #expect(texts(BlockEditing.settlingChecked(parent, blockID: parent.blocks[0].id)) == ["p2", "p1", "c1", "c2"])
    }

    @Test func aRowAloneOrAlreadyInPlaceDoesNotMove() {
        var alone = note([row("Text", .paragraph), row("only")])
        alone.blocks[1].isChecked = true
        #expect(BlockEditing.settlingChecked(alone, blockID: alone.blocks[1].id) == nil)
        var last = note([row("a"), row("b")])
        last.blocks[1].isChecked = true
        #expect(BlockEditing.settlingChecked(last, blockID: last.blocks[1].id) == nil)
    }
}

@MainActor
@Suite struct RowSortingModelTests {
    private func editor(_ blocks: [NoteBlock], deps: AppDependencies) throws -> NoteEditorModel {
        let note = Note(createdAt: .now, manualRank: "i", blocks: blocks)
        try deps.notes.save(note)
        return NoteEditorModel(note: note, repository: deps.notes, autosaveDelay: .seconds(60))
    }

    @Test func checkingMovesTheRowAndIsOneUndoStep() throws {
        let deps = try AppDependencies.inMemory()
        let e = try editor([
            NoteBlock(type: .checklistItem, rank: "a", content: RichText(plain: "one")),
            NoteBlock(type: .checklistItem, rank: "b", content: RichText(plain: "two")),
        ], deps: deps)
        e.toggleChecked(e.note.blocks[0].id)
        #expect(e.note.blocks.map(\.content.plainText) == ["two", "one"])
        #expect(e.note.blocks[1].isChecked)
        e.undo()
        #expect(e.note.blocks.map(\.content.plainText) == ["one", "two"])
        #expect(!e.note.blocks[0].isChecked)

        e.movesCheckedRowsDown = false
        e.toggleChecked(e.note.blocks[0].id)
        #expect(e.note.blocks.map(\.content.plainText) == ["one", "two"])
    }

    @Test func sortingSavesAndUndoes() throws {
        let deps = try AppDependencies.inMemory()
        let e = try editor([
            NoteBlock(type: .bulletItem, rank: "a", content: RichText(plain: "low"), tag: .priority(.low)),
            NoteBlock(type: .bulletItem, rank: "b", content: RichText(plain: "high"), tag: .priority(.high)),
        ], deps: deps)
        e.sortRows(by: .severity)
        e.flush()
        #expect(try deps.notes.note(id: e.note.id)?.blocks.map(\.content.plainText) == ["high", "low"])
        e.undo()
        #expect(e.note.blocks.map(\.content.plainText) == ["low", "high"])
    }

    @Test func preferenceIsSavedAndReachesTheEditor() throws {
        let deps = try AppDependencies.inMemory()
        let notes = NotesModel(repository: deps.notes, settings: deps.settings)
        #expect(notes.movesCheckedRowsDown)
        let note = Note(createdAt: .now, manualRank: "i", blocks: [NoteBlock(rank: "a", content: RichText(plain: "x"))])
        try deps.notes.save(note)
        notes.select(note.id)
        notes.movesCheckedRowsDown = false
        #expect(notes.editor?.movesCheckedRowsDown == false)
        #expect(deps.settings.load().movesCheckedRowsDown == false)
        #expect(NotesModel(repository: deps.notes, settings: deps.settings).movesCheckedRowsDown == false)
    }
}

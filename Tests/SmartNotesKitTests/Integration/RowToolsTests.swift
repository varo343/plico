import AppKit
import Foundation
import Testing
@testable import SmartNotesKit

@Suite struct RowToolsTests {
    private func note(_ blocks: [NoteBlock]) -> Note {
        Note(createdAt: .now, manualRank: "i", blocks: blocks)
    }

    @Test func duplicateGoesRightBelowWithEverything() throws {
        let picture = TestImages.image()
        let row = NoteBlock(type: .checklistItem, rank: "a", content: RichText(plain: "Call"), isChecked: true, indentLevel: 1,
                            tag: .priority(.high), detail: RichText(plain: "Draft"), image: picture, imageWidth: 120)
        let note = note([row, NoteBlock(rank: "b", content: RichText(plain: "Next"))])
        let result = try #require(BlockEditing.duplicate(note, blockID: row.id))
        #expect(result.note.blocks.map(\.content.plainText) == ["Call", "Call", "Next"])
        let copy = result.note.blocks[1]
        #expect(copy.id != row.id && result.focusBlockID == copy.id)
        #expect(copy.type == .checklistItem && copy.isChecked && copy.indentLevel == 1 && copy.tag == .priority(.high))
        #expect(copy.detail.plainText == "Draft" && copy.image == picture && copy.imageWidth == 120)
    }

    @Test func optionDragDropsACopyAndKeepsTheRow() throws {
        let note = note([NoteBlock(rank: "a", content: RichText(plain: "A")), NoteBlock(rank: "b", content: RichText(plain: "B")),
                         NoteBlock(rank: "c", content: RichText(plain: "R"), column: 1)])
        let below = try #require(BlockEditing.duplicate(note, blockID: note.blocks[0].id, relativeTo: note.blocks[1].id, placeAfter: true))
        #expect(below.note.blocks.map(\.content.plainText) == ["A", "B", "A", "R"])
        // Onto the other column: the copy takes that column.
        let across = try #require(BlockEditing.duplicate(note, blockID: note.blocks[0].id, relativeTo: note.blocks[2].id, placeAfter: false))
        #expect(across.note.blocks.map(\.content.plainText) == ["A", "B", "A", "R"])
        #expect(across.note.blocks.map(\.column) == [0, 0, 1, 1])
        // Beside a one-column note: the copy starts the right column.
        let single = self.note([NoteBlock(rank: "a", content: RichText(plain: "A"))])
        let started = try #require(BlockEditing.duplicate(single, blockID: single.blocks[0].id, toColumn: 1))
        #expect(started.note.blocks.map(\.column) == [0, 1])
    }

    @Test func copyRowKeepsTheWholeBlock() {
        let row = NoteBlock(type: .bulletItem, rank: "a", content: RichText(plain: "Item"), tag: .custom("Ops"))
        let paragraphs = BlockEditing.paragraphs(of: note([row]), blockIDs: [row.id])
        #expect(paragraphs == [PastedParagraph(type: .bulletItem, content: RichText(plain: "Item"), tag: .custom("Ops"))])
    }
}

@MainActor
@Suite(.serialized) struct RowMenuTests {
    private func makeEditor(_ blocks: [NoteBlock]) throws -> NoteEditorModel {
        let deps = try AppDependencies.inMemory()
        let note = Note(createdAt: .now, manualRank: "i", blocks: blocks)
        try deps.notes.save(note)
        return NoteEditorModel(note: note, repository: deps.notes, autosaveDelay: .seconds(60))
    }

    private func items(_ id: UUID, _ editor: NoteEditorModel) -> [SNMenuItem] {
        RowMenu.entries(for: id, model: editor, openImage: { _ in }).compactMap { if case .item(let item) = $0 { item } else { nil } }
    }

    private func run(_ title: String, _ id: UUID, _ editor: NoteEditorModel) throws {
        try #require(items(id, editor).first { $0.title == title }).action()
    }

    @Test func menuOffersTheRowTools() throws {
        let editor = try makeEditor([NoteBlock(rank: "a", content: RichText(plain: "One")), NoteBlock(rank: "b", content: RichText(plain: "Two"))])
        let id = editor.note.blocks[0].id
        let menu = items(id, editor)
        #expect(menu.map(\.title).starts(with: ["Duplicate", "Copy Row", "Move to Right Column"]))
        #expect(menu.last?.title == "Delete Row" && menu.last?.isDestructive == true)
        #expect(menu.allSatisfy { $0.icon != nil })

        try run("Duplicate", id, editor)
        #expect(editor.note.blocks.map(\.content.plainText) == ["One", "One", "Two"])
        try run("Move to Right Column", id, editor)
        #expect(editor.note.blocks.first { $0.id == id }?.column == 1)
        #expect(items(id, editor).contains { $0.title == "Move to Left Column" })
        try run("Delete Row", id, editor)
        #expect(editor.note.blocks.map(\.content.plainText) == ["One", "Two"])
        editor.undo()
        #expect(editor.note.blocks.count == 3)
    }

    @Test func copyRowWritesTheBlock() throws {
        let editor = try makeEditor([NoteBlock(type: .checklistItem, rank: "a", content: RichText(plain: "Milk"))])
        let board = NSPasteboard(name: .init("SmartNotesTests-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        BlockClipboard.write(editor.paragraphs(ofBlocks: [editor.note.blocks[0].id]), to: board)
        #expect(board.string(forType: .string) == "- [ ] Milk")
        let data = try #require(board.data(forType: .smartNotesBlocks))
        #expect(try PasteConverter.decode(data).map(\.content.plainText) == ["Milk"])
    }

    @Test func picturesAddTheirOwnTools() throws {
        let editor = try makeEditor([NoteBlock(rank: "a", content: RichText(plain: "Row"), image: TestImages.image(), imageWidth: 90)])
        let titles = items(editor.note.blocks[0].id, editor).map(\.title)
        #expect(titles.contains("Open Image") && titles.contains("Actual Size") && titles.contains("Move Image Out of the Row"))
    }

    /// The catcher over the grip and pictures must only take menu clicks, or
    /// dragging the grip and clicking a picture would stop working.
    @Test func catcherLetsOrdinaryClicksThrough() {
        let view = RowMenuCatcherView(frame: NSRect(x: 0, y: 0, width: 40, height: 40))
        #expect(view.hitTest(NSPoint(x: 10, y: 10)) == nil) // no current menu click
    }

    @Test func rightClickOnTextOpensThePlicoMenuAndSelectsTheRow() async throws {
        let h = try await EditorHarness.make(blocks: [(.paragraph, RichText(plain: "Hello")), (.paragraph, RichText(plain: "World"))])
        h.window.makeKeyAndOrderFront(nil)
        let view = h.textViews[0]
        let event = NSEvent.mouseEvent(with: .rightMouseDown, location: view.convert(NSPoint(x: 5, y: 5), to: nil), modifierFlags: [],
                                       timestamp: 0, windowNumber: h.window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        view.rightMouseDown(with: event)
        #expect(RowMenu.isOpen)
        #expect(h.window.childWindows?.count == 1) // a Plico panel, not an NSMenu
        #expect(h.editor.menuRowID == h.editor.note.blocks[0].id)
        RowMenu.close()
        #expect(h.editor.menuRowID == nil)
    }
}

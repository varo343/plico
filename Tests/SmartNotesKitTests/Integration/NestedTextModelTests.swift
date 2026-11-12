import Foundation
import SwiftData
import Testing
@testable import SmartNotesKit

@MainActor
@Suite struct NestedTextModelTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func makeEditor(_ blocks: [NoteBlock]) throws -> (NoteEditorModel, AppDependencies) {
        let deps = try AppDependencies.inMemory()
        let note = Note(createdAt: now, manualRank: "i", blocks: blocks)
        try deps.notes.save(note)
        return (NoteEditorModel(note: note, repository: deps.notes, autosaveDelay: .seconds(60), now: { [now] in now }), deps)
    }

    @Test func nestedTextIsCollapsedUntilToggled() throws {
        let (editor, _) = try makeEditor([NoteBlock(rank: "a", content: RichText(plain: "Email"), detail: RichText(plain: "Draft"))])
        let id = editor.note.blocks[0].id
        #expect(!editor.isDetailExpanded(id))
        editor.toggleDetail(id)
        #expect(editor.isDetailExpanded(id))
        #expect(editor.focusRequest == nil) // existing text: shown, caret stays put
        editor.toggleDetail(id)
        #expect(!editor.isDetailExpanded(id))
    }

    @Test func togglingAnEmptyBlockPutsTheCaretInNestedText() throws {
        let (editor, _) = try makeEditor([NoteBlock(rank: "a", content: RichText(plain: "Email"))])
        let id = editor.note.blocks[0].id
        editor.toggleDetail(id)
        #expect(editor.focusRequest?.blockID == id && editor.focusRequest?.isDetail == true)
    }

    @Test func formattingInNestedTextLeavesTheBlockAlone() throws {
        let (editor, _) = try makeEditor([NoteBlock(rank: "a", content: RichText(plain: "Email"), detail: RichText(plain: "Hello team"))])
        let id = editor.note.blocks[0].id
        editor.updateDetailSelection(blockID: id, range: 6..<10)
        editor.toggleMark(.bold, blockID: id, range: 6..<10, inDetail: true)
        #expect(editor.note.blocks[0].detail.runs == [TextRun("Hello "), TextRun("team", marks: [.bold])])
        #expect(editor.note.blocks[0].content == RichText(plain: "Email"))
        #expect(editor.selectionMarks == [.bold])

        editor.setFontSize(.large)
        #expect(editor.note.blocks[0].detail.runs.allSatisfy { $0.fontSize == .large || $0.text == "Hello " })
        #expect(editor.note.blocks[0].content.runs[0].fontSize == nil)
    }

    @Test func undoRestoresNestedTextAndItsCaret() throws {
        let (editor, _) = try makeEditor([NoteBlock(rank: "a", content: RichText(plain: "Email"))])
        let id = editor.note.blocks[0].id
        editor.updateDetailSelection(blockID: id, range: 0..<0)
        editor.setDetail(RichText(plain: "Draft"), ofBlock: id)
        editor.removeDetail(id)
        #expect(editor.note.blocks[0].detail.isEmpty && !editor.isDetailExpanded(id))
        editor.undo()
        #expect(editor.note.blocks[0].detail.plainText == "Draft")
        editor.undo()
        #expect(editor.note.blocks[0].detail.isEmpty)
        #expect(editor.focusRequest?.isDetail == true && editor.isDetailExpanded(id))
    }

    @Test func linksInNestedTextGoToNestedText() throws {
        let (editor, _) = try makeEditor([NoteBlock(rank: "a", content: RichText(plain: "Email"), detail: RichText(plain: "see site"))])
        let id = editor.note.blocks[0].id
        editor.beginLinkEditing(blockID: id, range: 4..<8, inDetail: true)
        editor.linkDraft?.url = "example.com"
        #expect(editor.commitLink())
        #expect(editor.note.blocks[0].detail.runs.last == TextRun("site", link: URL(string: "https://example.com")))
        #expect(editor.note.blocks[0].content == RichText(plain: "Email"))
    }

    @Test func roundTripsThroughTheStore() throws {
        let (editor, deps) = try makeEditor([NoteBlock(rank: "a", content: RichText(plain: "Email"))])
        let id = editor.note.blocks[0].id
        editor.setDetail(RichText(runs: [TextRun("Ciao "), TextRun("team", marks: [.bold])]), ofBlock: id)
        editor.flush()
        #expect(try deps.notes.note(id: editor.note.id)?.blocks[0].detail == editor.note.blocks[0].detail)
        #expect(try deps.notes.search("ciao team", in: .active).map(\.id) == [editor.note.id])
        editor.removeDetail(id)
        editor.flush()
        #expect(try deps.notes.note(id: editor.note.id)?.blocks[0].detail.isEmpty == true)
    }

    /// A store written by the previous version (schema V2, tags but no nested
    /// text) opens with notes and tags intact; nested text can then be saved.
    @Test func migratesAVersion2StoreKeepingNotes() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("SmartNotes.store")
        let noteID = UUID(), blockID = UUID()

        do {
            let schema = Schema(versionedSchema: SmartNotesSchemaV2.self)
            let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url))
            let context = ModelContext(container)
            let record = SmartNotesSchemaV2.NoteRecord(
                id: noteID, title: "Marketing", createdAt: now, updatedAt: now, isPinned: false, deletedAt: nil,
                priorityRaw: "none", plannedDay: nil, dueDay: nil, manualRank: Rank.initial, sourceExternalItemId: nil,
                searchText: "marketing", previewText: "", displayTitle: "Marketing"
            )
            context.insert(record)
            let block = SmartNotesSchemaV2.BlockRecord(
                id: blockID, typeRaw: BlockType.checklistItem.rawValue, rank: "a",
                contentData: try RichText(plain: "Email").encodedData(), isChecked: false, indentLevel: 0, tagRaw: "priority:high"
            )
            context.insert(block)
            block.note = record
            try context.save()
        }

        let repo = SwiftDataNoteRepository(container: try PersistenceController.makeContainer(.onDisk(url)))
        var note = try #require(try repo.note(id: noteID))
        #expect(note.title == "Marketing")
        #expect(note.blocks.map(\.id) == [blockID])
        #expect(note.blocks[0].tag == .priority(.high))
        #expect(note.blocks[0].detail.isEmpty)

        note.blocks[0].detail = RichText(plain: "Draft")
        try repo.save(note)
        #expect(try repo.note(id: noteID)?.blocks[0].detail.plainText == "Draft")
    }
}

@MainActor
@Suite struct NestBlockModelTests {
    @Test func nestingIsOneUndoStepAndStaysCollapsed() throws {
        let deps = try AppDependencies.inMemory()
        let note = Note(createdAt: .now, manualRank: "i", blocks: [
            NoteBlock(rank: "a", content: RichText(plain: "Email")),
            NoteBlock(rank: "b", content: RichText(plain: "Draft")),
        ])
        try deps.notes.save(note)
        let editor = NoteEditorModel(note: note, repository: deps.notes, autosaveDelay: .seconds(60))
        let (target, dragged) = (note.blocks[0].id, note.blocks[1].id)

        editor.nestBlock(dragged, into: target)
        #expect(editor.note.blocks.map(\.content.plainText) == ["Email"])
        #expect(editor.note.blocks[0].detail.plainText == "Draft")
        #expect(!editor.isDetailExpanded(target))
        #expect(editor.focusRequest?.blockID == target && editor.focusRequest?.isDetail == false)

        editor.flush()
        #expect(try deps.notes.note(id: note.id)?.blocks.map(\.detail.plainText) == ["Draft"])

        editor.undo()
        #expect(editor.note.blocks.map(\.content.plainText) == ["Email", "Draft"])
        #expect(editor.note.blocks[0].detail.isEmpty)
    }
}

@MainActor
@Suite struct NestedRowModelTests {
    @Test func draggingANestedRowOutIsOneUndoStep() throws {
        let deps = try AppDependencies.inMemory()
        let note = Note(createdAt: .now, manualRank: "i", blocks: [
            NoteBlock(rank: "a", content: RichText(plain: "Email"), detail: RichText(plain: "• Draft")),
            NoteBlock(rank: "b", content: RichText(plain: "Next")),
        ])
        try deps.notes.save(note)
        let editor = NoteEditorModel(note: note, repository: deps.notes, autosaveDelay: .seconds(60))
        let id = note.blocks[0].id
        editor.toggleDetail(id)

        editor.unnestRow(0..<7, of: id, relativeTo: note.blocks[1].id, placeAfter: false)
        #expect(editor.note.blocks.map(\.content.plainText) == ["Email", "Draft", "Next"])
        #expect(editor.note.blocks[1].type == .bulletItem)
        #expect(editor.note.blocks[0].detail.isEmpty && !editor.isDetailExpanded(id))
        #expect(editor.focusRequest?.blockID == editor.note.blocks[1].id)

        editor.undo()
        #expect(editor.note.blocks.map(\.content.plainText) == ["Email", "Next"])
        #expect(editor.note.blocks[0].detail.plainText == "• Draft")
    }

    @Test func movingANestedRowToAnotherRowSaves() throws {
        let deps = try AppDependencies.inMemory()
        let note = Note(createdAt: .now, manualRank: "i", blocks: [
            NoteBlock(rank: "a", content: RichText(plain: "A"), detail: RichText(plain: "one\ntwo")),
            NoteBlock(rank: "b", content: RichText(plain: "B")),
        ])
        try deps.notes.save(note)
        let editor = NoteEditorModel(note: note, repository: deps.notes, autosaveDelay: .seconds(60))

        editor.moveNestedRow(4..<7, of: note.blocks[0].id, into: note.blocks[1].id)
        editor.flush()
        #expect(try deps.notes.note(id: note.id)?.blocks.map(\.detail.plainText) == ["one", "two"])
    }
}

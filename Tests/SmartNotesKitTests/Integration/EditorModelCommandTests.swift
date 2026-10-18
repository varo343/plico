import Foundation
import Testing
@testable import SmartNotesKit

@MainActor
@Suite struct EditorModelCommandTests {
    private func makeEditor(_ specs: [(BlockType, RichText)]) throws -> (NoteEditorModel, AppDependencies, TestClock) {
        let deps = try AppDependencies.inMemory()
        let clock = TestClock(Date(timeIntervalSince1970: 1_790_000_000))
        let ranks = Rank.evenlySpaced(specs.count)
        let note = Note(createdAt: clock.now, manualRank: "i", blocks: zip(specs, ranks).map {
            NoteBlock(type: $0.0, rank: $1, content: $0.1)
        })
        try deps.notes.save(note)
        let editor = NoteEditorModel(note: note, repository: deps.notes, autosaveDelay: .seconds(60), now: { clock.now })
        return (editor, deps, clock)
    }

    private func texts(_ editor: NoteEditorModel) -> [String] { editor.note.blocks.map(\.content.plainText) }

    @Test func undoRedoAcrossTypingSplitAndMove() throws {
        let (editor, _, clock) = try makeEditor([(.paragraph, RichText(plain: "A")), (.paragraph, RichText(plain: "B"))])
        let a = editor.note.blocks[0].id
        editor.updateSelection(blockID: a, range: 1..<1)
        editor.setContent(RichText(plain: "Ab"), ofBlock: a)
        clock.advance(0.3)
        editor.setContent(RichText(plain: "Abc"), ofBlock: a)   // coalesced with previous
        editor.splitBlock(a, atUTF16Offset: 1)                    // "A" | "bc" | "B"
        editor.moveBlock(editor.note.blocks[2].id, by: -2)         // "B" | "A" | "bc"
        #expect(texts(editor) == ["B", "A", "bc"])

        editor.undo(); #expect(texts(editor) == ["A", "bc", "B"])
        editor.undo(); #expect(texts(editor) == ["Abc", "B"])
        editor.undo(); #expect(texts(editor) == ["A", "B"])     // whole typing run at once
        #expect(!editor.canUndo)
        editor.redo(); editor.redo(); editor.redo()
        #expect(texts(editor) == ["B", "A", "bc"])
        #expect(!editor.canRedo)
    }

    @Test func undoRestoresFormattingAndCheckState() throws {
        let (editor, _, _) = try makeEditor([(.checklistItem, RichText(plain: "Task"))])
        let id = editor.note.blocks[0].id
        editor.toggleMark(.bold, blockID: id, range: 0..<4)
        editor.toggleChecked(id)
        #expect(editor.note.blocks[0].isChecked && editor.note.blocks[0].content.runs[0].marks == [.bold])
        editor.undo()
        #expect(!editor.note.blocks[0].isChecked)
        editor.undo()
        #expect(editor.note.blocks[0].content == RichText(plain: "Task"))
    }

    @Test func undoIsPersistedByAutosave() throws {
        let (editor, deps, _) = try makeEditor([(.paragraph, RichText(plain: "keep"))])
        let id = editor.note.blocks[0].id
        editor.setContent(RichText(plain: "changed"), ofBlock: id)
        editor.flush()
        editor.undo()
        editor.flush()
        #expect(try deps.notes.note(id: editor.note.id)?.blocks[0].content.plainText == "keep")
    }

    @Test func toggleMarkKeepsSelectionAndUpdatesToolbarState() throws {
        let (editor, _, _) = try makeEditor([(.paragraph, RichText(plain: "Hello world"))])
        let id = editor.note.blocks[0].id
        editor.updateSelection(blockID: id, range: 0..<5)
        #expect(editor.hasTextSelection && editor.selectionMarks.isEmpty)
        editor.toggleMark(.italic, blockID: id, range: 0..<5)
        #expect(editor.selectionMarks == [.italic])
        #expect(editor.focusRequest?.offset == 0 && editor.focusRequest?.length == 5)
    }

    @Test func blockTypeAndIndentTargetActiveBlock() throws {
        let (editor, _, _) = try makeEditor([(.paragraph, RichText(plain: "a")), (.paragraph, RichText(plain: "b"))])
        let b = editor.note.blocks[1].id
        editor.updateSelection(blockID: b, range: 0..<0)
        editor.setBlockType(.bulletItem)
        #expect(editor.note.blocks[1].type == .bulletItem)
        #expect(editor.indentBlock(b, by: 1))
        #expect(editor.note.blocks[1].indentLevel == 1)
        #expect(!editor.indentBlock(editor.note.blocks[0].id, by: 1)) // paragraphs don't indent
    }

    @Test func fontPresetsApplyToSelectionOrWholeBlock() throws {
        let (editor, _, _) = try makeEditor([(.paragraph, RichText(plain: "abcdef"))])
        let id = editor.note.blocks[0].id
        editor.updateSelection(blockID: id, range: 0..<3)
        editor.setFontFamily(.serif)
        #expect(editor.note.blocks[0].content.runs == [TextRun("abc", fontFamily: .serif), TextRun("def")])
        editor.updateSelection(blockID: id, range: 2..<2)
        editor.setFontSize(.large)
        #expect(editor.note.blocks[0].content.runs.allSatisfy { $0.fontSize == .large })
    }

    @Test func linkCommitValidatesAndApplies() throws {
        let (editor, _, _) = try makeEditor([(.paragraph, RichText(plain: "see docs here"))])
        let id = editor.note.blocks[0].id
        editor.beginLinkEditing(blockID: id, range: 4..<8)
        editor.linkDraft?.url = "javascript:alert(1)"
        #expect(!editor.commitLink())
        #expect(editor.linkError != nil && editor.linkDraft != nil)
        editor.linkDraft?.url = "developer.apple.com"
        #expect(editor.commitLink())
        #expect(editor.note.blocks[0].content.commonLink(in: 4..<8) == URL(string: "https://developer.apple.com"))

        editor.beginLinkEditing(blockID: id, range: 4..<8)
        #expect(editor.linkDraft?.hasExistingLink == true)
        editor.removeLink()
        #expect(editor.note.blocks[0].content == RichText(plain: "see docs here"))
    }

    @Test func linkWithoutSelectionInsertsAddress() throws {
        let (editor, _, _) = try makeEditor([(.paragraph, RichText(plain: "Go: "))])
        let id = editor.note.blocks[0].id
        editor.beginLinkEditing(blockID: id, range: 4..<4)
        editor.linkDraft?.url = "https://example.com"
        editor.commitLink()
        #expect(editor.note.blocks[0].content.runs == [TextRun("Go: "), TextRun("https://example.com", link: URL(string: "https://example.com"))])
    }

    @Test func pasteIsOneUndoStep() throws {
        let (editor, _, _) = try makeEditor([(.paragraph, RichText(plain: "ab"))])
        let id = editor.note.blocks[0].id
        editor.paste([PastedParagraph(content: RichText(plain: "1")), PastedParagraph(content: RichText(plain: "2"))], blockID: id, range: 1..<1)
        #expect(texts(editor) == ["a1", "2b"])
        editor.undo()
        #expect(texts(editor) == ["ab"])
    }

    // MARK: Multi-block selection

    private func range(_ editor: NoteEditorModel, from: (Int, Int), to: (Int, Int)) {
        let blocks = editor.note.blocks
        editor.setRangeSelection(anchor: BlockPosition(blockID: blocks[from.0].id, offset: from.1),
                                 focus: BlockPosition(blockID: blocks[to.0].id, offset: to.1))
    }

    @Test func typingOverMultiBlockSelectionReplacesItInOneUndoStep() throws {
        let (editor, _, _) = try makeEditor([(.paragraph, RichText(plain: "Hello")), (.bulletItem, RichText(plain: "list")), (.paragraph, RichText(plain: "world"))])
        range(editor, from: (0, 2), to: (2, 3))
        #expect(editor.hasTextSelection)
        editor.replaceRangeSelection(with: "y")
        #expect(texts(editor) == ["Heyld"])
        #expect(editor.rangeSelection == nil)
        editor.undo()
        #expect(texts(editor) == ["Hello", "list", "world"])
    }

    @Test func formattingAndBlockTypeApplyToTheWholeSelection() throws {
        let (editor, _, _) = try makeEditor([(.paragraph, RichText(plain: "one")), (.paragraph, RichText(plain: "two")), (.paragraph, RichText(plain: "three"))])
        range(editor, from: (0, 0), to: (2, 5))
        editor.toggleMark(.bold, blockID: editor.note.blocks[0].id, range: 0..<0)
        #expect(editor.note.blocks.allSatisfy { $0.content.commonMarks(in: 0..<$0.content.utf16Length) == [.bold] })
        #expect(editor.selectionMarks == [.bold])
        editor.setBlockType(.checklistItem)
        #expect(editor.note.blocks.map(\.type) == [.checklistItem, .checklistItem, .checklistItem])
        #expect(editor.rangeSelection != nil) // still selected for the next command
    }

    @Test func selectAllCoversEveryBlockAndSingleBlockRangeClears() throws {
        let (editor, _, _) = try makeEditor([(.paragraph, RichText(plain: "a")), (.paragraph, RichText(plain: "bc"))])
        editor.selectAllBlocks()
        #expect(editor.rangeSegments.map(\.range) == [0..<1, 0..<2])
        range(editor, from: (1, 0), to: (1, 2))
        #expect(editor.rangeSelection == nil)
    }
}

import Foundation
import Testing
@testable import SmartNotesKit

/// Controllable clock for deterministic timestamps.
@MainActor
final class TestClock {
    var now: Date
    init(_ start: Date) { now = start }
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

@MainActor
@Suite struct NotesModelTests {
    private let start = Date(timeIntervalSince1970: 1_790_000_000)

    private func makeModel(seed: Bool = true) throws -> (NotesModel, AppDependencies, TestClock) {
        let deps = try AppDependencies.inMemory(seedSampleData: seed, now: start)
        let clock = TestClock(start)
        // Long autosave delay: tests drive saving explicitly via flush().
        let model = NotesModel(repository: deps.notes, settings: deps.settings, autosaveDelay: .seconds(60), now: { clock.now })
        model.load()
        return (model, deps, clock)
    }

    @Test func loadOpensMostRecentlyEditedNote() throws {
        let (model, _, _) = try makeModel()
        // Fixtures get fresh IDs per call, so compare by title.
        let expected = SampleData.notes(now: start).max { $0.updatedAt < $1.updatedAt }!
        #expect(model.editor?.note.title == expected.title)
        #expect(model.selectedNoteID == model.editor?.note.id)
    }

    @Test func createNoteGoesToTopSelectsAndFocusesBody() throws {
        let (model, deps, _) = try makeModel()
        model.searchQuery = "quarterly"
        model.createNote()
        let id = try #require(model.selectedNoteID)
        #expect(model.searchQuery.isEmpty)
        #expect(model.groups.others.first?.id == id) // manual sort: top of unpinned
        let editor = try #require(model.editor)
        #expect(editor.focusRequest?.blockID == editor.note.blocks.first?.id)
        #expect(try deps.notes.note(id: id) != nil) // persisted immediately
    }

    @Test func editsPersistOnFlushAndRefreshList() throws {
        let (model, deps, clock) = try makeModel()
        model.createNote()
        let editor = try #require(model.editor)
        clock.advance(30)
        editor.setTitle("Groceries")
        editor.setContent(RichText(runs: [TextRun("Eggs", marks: [.bold])]), ofBlock: editor.note.blocks[0].id)
        #expect(editor.hasUnsavedChanges)

        model.flush()
        #expect(!editor.hasUnsavedChanges)
        let stored = try #require(try deps.notes.note(id: editor.note.id))
        #expect(stored.title == "Groceries")
        #expect(stored.blocks[0].content.runs == [TextRun("Eggs", marks: [.bold])])
        #expect(stored.updatedAt == clock.now)
        #expect(model.groups.all.first { $0.id == stored.id }?.displayTitle == "Groceries")
    }

    @Test func switchingNotesFlushesPendingEdits() throws {
        let (model, deps, _) = try makeModel()
        let editor = try #require(model.editor)
        editor.setTitle("Changed before switching")
        let other = try #require(model.groups.all.first { $0.id != editor.note.id })
        model.select(other.id)
        #expect(try deps.notes.note(id: editor.note.id)?.title == "Changed before switching")
    }

    @Test func autosaveFiresAfterDebounce() async throws {
        let deps = try AppDependencies.inMemory(seedSampleData: true, now: start)
        let model = NotesModel(repository: deps.notes, settings: deps.settings, autosaveDelay: .milliseconds(20))
        model.load()
        let editor = try #require(model.editor)
        editor.setTitle("Debounced")
        #expect(try deps.notes.note(id: editor.note.id)?.title != "Debounced")
        // Poll rather than sleep a fixed time: parallel main-actor tests can delay the save.
        let deadline = ContinuousClock.now + .seconds(5)
        while editor.hasUnsavedChanges, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(try deps.notes.note(id: editor.note.id)?.title == "Debounced")
        #expect(!editor.hasUnsavedChanges)
    }

    @Test func pendingAutosaveDoesNotUndoPin() throws {
        let (model, deps, _) = try makeModel()
        let editor = try #require(model.editor)
        let id = editor.note.id
        let wasPinned = editor.note.isPinned
        editor.setTitle("Typing…")
        model.togglePin(id)
        model.flush()
        let stored = try #require(try deps.notes.note(id: id))
        #expect(stored.isPinned == !wasPinned)
        #expect(stored.title == "Typing…")
    }

    @Test func trashSelectsNeighbourAndUndoRestores() throws {
        let (model, deps, _) = try makeModel()
        let ordered = model.groups.all
        let target = ordered[1]
        model.select(target.id)
        model.moveToTrash(target.id)

        #expect(!model.groups.all.contains { $0.id == target.id })
        #expect(model.selectedNoteID == ordered[2].id)
        #expect(model.recentlyTrashed?.id == target.id)
        #expect(model.trashed.map(\.id) == [target.id])

        model.undoTrash()
        #expect(model.groups.all.map(\.id) == ordered.map(\.id))
        #expect(model.selectedNoteID == target.id)
        #expect(try deps.notes.note(id: target.id)?.isTrashed == false)
    }

    @Test func emptyTrashAndPermanentDelete() throws {
        let (model, _, _) = try makeModel()
        let ids = model.groups.all.prefix(3).map(\.id)
        ids.forEach(model.moveToTrash)
        model.deletePermanently(ids[0])
        #expect(model.trashed.count == 2)
        model.emptyTrash()
        #expect(model.trashed.isEmpty)
        #expect(model.recentlyTrashed == nil)
    }

    @Test func searchFiltersAndManualDragIsDisabledWhileSearching() throws {
        let (model, _, _) = try makeModel()
        #expect(model.canReorder)
        model.searchQuery = "COFFEE"
        #expect(model.groups.all.map(\.title) == ["Weekend errands"])
        #expect(!model.canReorder)
        model.searchQuery = "zzz-nothing"
        #expect(model.groups.all.isEmpty && model.hasAnyNotes)
    }

    @Test func sortModePersistsAndDisablesReorder() throws {
        let (model, deps, _) = try makeModel()
        model.sortMode = .title
        #expect(!model.canReorder)
        #expect(deps.settings.load().sortMode == .title)
        let titles = model.groups.others.map(\.displayTitle)
        #expect(titles == titles.sorted { $0.localizedStandardCompare($1) == .orderedAscending })

        let fresh = NotesModel(repository: deps.notes, settings: deps.settings)
        #expect(fresh.sortMode == .title)
    }

    @Test func manualReorderPersists() throws {
        let (model, deps, _) = try makeModel()
        let before = model.groups.others.map(\.id)
        model.move(inPinnedGroup: false, from: [0], to: before.count)
        let expected = Array(before.dropFirst()) + [before[0]]
        #expect(model.groups.others.map(\.id) == expected)

        let reloaded = NotesModel(repository: deps.notes, settings: deps.settings)
        reloaded.load()
        #expect(reloaded.groups.others.map(\.id) == expected)
    }

    @Test func moveIsIgnoredOutsideManualSort() throws {
        let (model, _, _) = try makeModel()
        model.sortMode = .updated
        let before = model.groups.others.map(\.id)
        model.move(inPinnedGroup: false, from: [0], to: 2)
        #expect(model.groups.others.map(\.id) == before)
    }

    @Test func duplicatePlacesCopyAfterOriginalAndSelectsIt() throws {
        let (model, _, _) = try makeModel()
        let original = model.groups.others[0]
        model.duplicate(original.id)
        let others = model.groups.others
        #expect(others[0].id == original.id)
        #expect(others[1].title == original.title && others[1].id != original.id)
        #expect(model.selectedNoteID == others[1].id)
    }

    @Test func pinMovesNoteToPinnedGroup() throws {
        let (model, _, _) = try makeModel()
        let note = model.groups.others[0]
        model.togglePin(note.id)
        #expect(model.groups.pinned.contains { $0.id == note.id })
        model.togglePin(note.id)
        #expect(model.groups.others.contains { $0.id == note.id })
    }

    @Test func emptyStoreHasNoNotesAndNoSelection() throws {
        let (model, _, _) = try makeModel(seed: false)
        #expect(!model.hasAnyNotes)
        #expect(model.selectedNoteID == nil && model.editor == nil)
    }
}

@MainActor
@Suite struct NoteEditorModelTests {
    private let start = Date(timeIntervalSince1970: 1_790_000_000)

    @Test func enterAndBackspaceRoundTripAndFocus() throws {
        let deps = try AppDependencies.inMemory()
        let note = Note(createdAt: start, manualRank: "i", blocks: [NoteBlock(rank: "i", content: RichText(plain: "HelloWorld"))])
        try deps.notes.save(note)
        let editor = NoteEditorModel(note: note, repository: deps.notes, autosaveDelay: .seconds(60))

        editor.splitBlock(note.blocks[0].id, atUTF16Offset: 5)
        #expect(editor.note.blocks.map(\.content.plainText) == ["Hello", "World"])
        #expect(editor.focusRequest?.blockID == editor.note.blocks[1].id)

        #expect(editor.mergeBlockWithPrevious(editor.note.blocks[1].id))
        #expect(editor.note.blocks.map(\.content.plainText) == ["HelloWorld"])
        #expect(editor.focusRequest?.offset == 5)

        editor.flush()
        #expect(try deps.notes.note(id: note.id)?.blocks.map(\.content.plainText) == ["HelloWorld"])
    }

    @Test func emptyNoteGetsAnEditableBlockWithoutBeingDirty() throws {
        let deps = try AppDependencies.inMemory()
        let editor = NoteEditorModel(note: Note(createdAt: start, manualRank: "i"), repository: deps.notes)
        #expect(editor.note.blocks.count == 1)
        #expect(!editor.hasUnsavedChanges)
    }

    @Test func noOpEditsDoNotDirtyOrBumpUpdatedAt() throws {
        let deps = try AppDependencies.inMemory()
        let note = SampleData.notes(now: start)[0]
        try deps.notes.save(note)
        let editor = NoteEditorModel(note: note, repository: deps.notes, now: { Date(timeIntervalSince1970: 0) })
        editor.setTitle(note.title)
        editor.setContent(note.blocks[0].content, ofBlock: note.blocks[0].id)
        #expect(!editor.hasUnsavedChanges)
        #expect(editor.note.updatedAt == note.updatedAt)
    }

    @Test func checklistToggleOnlyAffectsChecklistItems() throws {
        let deps = try AppDependencies.inMemory()
        let note = SampleData.notes(now: start)[1] // checklist note
        try deps.notes.save(note)
        let editor = NoteEditorModel(note: note, repository: deps.notes)
        let first = editor.note.blocks[0]
        editor.toggleChecked(first.id)
        #expect(editor.note.blocks[0].isChecked == !first.isChecked)

        let paragraphNote = SampleData.notes(now: start)[0]
        let other = NoteEditorModel(note: paragraphNote, repository: deps.notes)
        other.toggleChecked(paragraphNote.blocks[0].id) // heading: ignored
        #expect(!other.hasUnsavedChanges)
    }

    @Test func failedSaveKeepsChangesAndReportsError() throws {
        let deps = try AppDependencies.inMemory()
        // Never saved → updateContent throws noteNotFound, simulating a write failure.
        let note = Note(createdAt: start, manualRank: "i")
        let editor = NoteEditorModel(note: note, repository: deps.notes, autosaveDelay: .seconds(60))
        editor.setTitle("Precious words")
        editor.flush()
        #expect(editor.saveError != nil)
        #expect(editor.hasUnsavedChanges)
        #expect(editor.note.title == "Precious words")

        try deps.notes.save(Note(id: note.id, createdAt: start, manualRank: "i"))
        editor.flush()
        #expect(editor.saveError == nil && !editor.hasUnsavedChanges)
        #expect(try deps.notes.note(id: note.id)?.title == "Precious words")
    }

    @Test func arrowNavigationBetweenBlocks() throws {
        let deps = try AppDependencies.inMemory()
        let note = SampleData.notes(now: start)[1]
        let editor = NoteEditorModel(note: note, repository: deps.notes)
        let ids = editor.note.blocks.map(\.id)
        #expect(!editor.focusPrevious(before: ids[0]))
        #expect(editor.focusNext(after: ids[0]))
        #expect(editor.focusRequest == FocusRequest(blockID: ids[1], offset: 0).with(token: editor.focusRequest!.token))
        #expect(editor.focusPrevious(before: ids[1]))
        #expect(editor.focusRequest?.blockID == ids[0] && editor.focusRequest?.offset == .max)
        #expect(!editor.focusNext(after: ids.last!))
    }
}

private extension FocusRequest {
    func with(token: UUID) -> FocusRequest {
        var copy = self
        copy.token = token
        return copy
    }
}

@MainActor
@Suite struct NotesListNavigationTests {
    private let start = Date(timeIntervalSince1970: 1_790_000_000)

    private func makeModel() throws -> NotesModel {
        let deps = try AppDependencies.inMemory(seedSampleData: true, now: start)
        let model = NotesModel(repository: deps.notes, settings: deps.settings, autosaveDelay: .seconds(60))
        model.load()
        return model
    }

    @Test func arrowKeysWalkTheVisibleOrderAndStopAtEnds() throws {
        let model = try makeModel()
        let ordered = model.groups.all.map(\.id)
        model.select(ordered[0])
        model.selectAdjacent(-1)
        #expect(model.selectedNoteID == ordered[0])
        model.selectAdjacent(1); model.selectAdjacent(1)
        #expect(model.selectedNoteID == ordered[2])
        for _ in 0..<10 { model.selectAdjacent(1) }
        #expect(model.selectedNoteID == ordered.last)
    }

    @Test func dragMovesWithinGroupOnly() throws {
        let model = try makeModel()
        let others = model.groups.others.map(\.id)
        model.moveNote(others[0], relativeTo: others[2], placeAfter: true)
        #expect(model.groups.others.map(\.id) == [others[1], others[2], others[0], others[3]])
        let pinned = try #require(model.groups.pinned.first?.id)
        model.moveNote(pinned, relativeTo: others[1], placeAfter: false) // across groups: ignored
        #expect(model.groups.pinned.first?.id == pinned)
    }
}

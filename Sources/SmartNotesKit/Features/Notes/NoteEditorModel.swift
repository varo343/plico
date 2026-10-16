import Foundation
import Observation

/// Where the caret should go next. `token` makes repeated requests distinct.
public struct FocusRequest: Equatable, Sendable {
    public var blockID: UUID
    public var offset: Int
    /// False when the caret should not pull the view (e.g. opening a note).
    public var scrollsIntoView: Bool
    public var token = UUID()

    /// Use `Int.max` to place the caret at the end of the block.
    public init(blockID: UUID, offset: Int, scrollsIntoView: Bool = true) {
        self.blockID = blockID
        self.offset = offset
        self.scrollsIntoView = scrollsIntoView
    }
}

/// Editing session for one note: holds the working copy, applies edits, and
/// autosaves with a short debounce. Content is written through
/// `updateContent`, so metadata changed elsewhere is never overwritten.
@MainActor
@Observable
public final class NoteEditorModel {
    public private(set) var note: Note
    public var focusRequest: FocusRequest?
    /// Non-nil while the latest changes are not persisted. Cleared only by a successful save.
    public private(set) var saveError: String?
    public private(set) var hasUnsavedChanges = false

    @ObservationIgnored private let repository: NoteRepository
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let autosaveDelay: Duration
    @ObservationIgnored private let onSaved: (UUID) -> Void
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    public init(
        note: Note,
        repository: NoteRepository,
        autosaveDelay: Duration = .milliseconds(400),
        now: @escaping () -> Date = Date.init,
        onSaved: @escaping (UUID) -> Void = { _ in }
    ) {
        self.note = BlockEditing.ensuringEditableBlock(note)
        self.repository = repository
        self.autosaveDelay = autosaveDelay
        self.now = now
        self.onSaved = onSaved
    }

    // MARK: Edits

    public func setTitle(_ title: String) {
        guard title != note.title else { return }
        note.title = title
        markChanged()
    }

    public func setContent(_ content: RichText, ofBlock id: UUID) {
        guard let index = index(of: id), note.blocks[index].content != content else { return }
        note.blocks[index].content = content
        markChanged()
    }

    public func toggleChecked(_ id: UUID) {
        guard let index = index(of: id), note.blocks[index].type == .checklistItem else { return }
        note.blocks[index].isChecked.toggle()
        markChanged()
    }

    /// Enter.
    public func splitBlock(_ id: UUID, atUTF16Offset offset: Int) {
        apply { try BlockEditing.split($0, blockID: id, atUTF16Offset: offset) }
    }

    /// Backspace at the start of a block. Returns false when nothing changed.
    @discardableResult
    public func mergeBlockWithPrevious(_ id: UUID) -> Bool {
        var changed = false
        apply { note in
            let result = try BlockEditing.mergeWithPrevious(note, blockID: id)
            changed = result != nil
            return result
        }
        return changed
    }

    // MARK: Focus

    public func focus(_ id: UUID, offset: Int, scrollsIntoView: Bool = true) {
        focusRequest = FocusRequest(blockID: id, offset: offset, scrollsIntoView: scrollsIntoView)
    }

    /// `scrollsIntoView: false` keeps the note scrolled to its top (title visible).
    public func focusFirstBlock(scrollsIntoView: Bool = true) {
        if let first = note.blocks.first { focus(first.id, offset: 0, scrollsIntoView: scrollsIntoView) }
    }

    public func focusLastBlockEnd() {
        if let last = note.blocks.last { focus(last.id, offset: .max) }
    }

    /// Moves the caret to the end of the previous block. Returns false at the first block.
    @discardableResult
    public func focusPrevious(before id: UUID) -> Bool {
        guard let index = index(of: id), index > 0 else { return false }
        focus(note.blocks[index - 1].id, offset: .max)
        return true
    }

    /// Moves the caret to the start of the next block. Returns false at the last block.
    @discardableResult
    public func focusNext(after id: UUID) -> Bool {
        guard let index = index(of: id), index + 1 < note.blocks.count else { return false }
        focus(note.blocks[index + 1].id, offset: 0)
        return true
    }

    // MARK: Saving

    /// Saves now if there are pending changes. Safe to call repeatedly.
    public func flush() {
        saveTask?.cancel()
        saveTask = nil
        guard hasUnsavedChanges else { return }
        do {
            try repository.updateContent(id: note.id, title: note.title, blocks: note.blocks, updatedAt: note.updatedAt)
            hasUnsavedChanges = false
            saveError = nil
            onSaved(note.id)
        } catch {
            // Keep the working copy and the dirty flag; never pretend it saved.
            saveError = error.localizedDescription
            Log.persistence.error("Autosave failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Private

    private func index(of id: UUID) -> Int? {
        note.blocks.firstIndex { $0.id == id }
    }

    private func apply(_ operation: (Note) throws -> BlockEditing.Result?) {
        do {
            guard let result = try operation(note) else { return }
            note = result.note
            markChanged()
            focus(result.focusBlockID, offset: result.focusOffset)
        } catch {
            Log.app.error("Block operation failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func markChanged() {
        note.updatedAt = now()
        hasUnsavedChanges = true
        scheduleSave()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let delay = autosaveDelay
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }
}

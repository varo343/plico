import Foundation
import Observation

/// Where the caret should go next. `token` makes repeated requests distinct.
public struct FocusRequest: Equatable, Sendable {
    public var blockID: UUID
    public var offset: Int
    /// Length of the selection to restore (0 = caret only).
    public var length: Int
    /// False when the caret should not pull the view (e.g. opening a note).
    public var scrollsIntoView: Bool
    public var token = UUID()

    /// Use `Int.max` to place the caret at the end of the block.
    public init(blockID: UUID, offset: Int, length: Int = 0, scrollsIntoView: Bool = true) {
        self.blockID = blockID
        self.offset = offset
        self.length = length
        self.scrollsIntoView = scrollsIntoView
    }
}

/// The current text selection inside one block (UTF-16 range).
public struct BlockSelection: Equatable, Sendable {
    public var blockID: UUID
    public var range: Range<Int>
}

/// The open slash menu: which block, the typed "/query" and the choices.
public struct SlashMenuState: Equatable {
    public var blockID: UUID
    public var range: Range<Int>
    public var query: String
    public var commands: [SlashCommand]
    public var highlighted: Int
    /// Screen rect of the "/" (where the menu is anchored).
    public var anchor: CGRect?
}

/// State for the ⌘K link sheet.
public struct LinkDraft: Equatable, Sendable {
    public var blockID: UUID
    public var range: Range<Int>
    public var url: String
    public var hasExistingLink: Bool
}

/// Editing session for one note: holds the working copy, applies edits, keeps
/// note-level undo/redo, and autosaves with a short debounce. Content is written
/// through `updateContent`, so metadata changed elsewhere is never overwritten.
@MainActor
@Observable
public final class NoteEditorModel {
    public private(set) var note: Note
    public var focusRequest: FocusRequest?
    /// Non-nil while the latest changes are not persisted. Cleared only by a successful save.
    public private(set) var saveError: String?
    public private(set) var hasUnsavedChanges = false
    public private(set) var canUndo = false
    public private(set) var canRedo = false
    /// True while some text is selected (shows the formatting bar).
    public private(set) var hasTextSelection = false
    /// Marks shared by the current selection, for toolbar state.
    public private(set) var selectionMarks: Set<InlineMark> = []
    /// Block containing the caret; target of block commands.
    public private(set) var activeBlockID: UUID?
    public var linkDraft: LinkDraft?
    public private(set) var slashMenu: SlashMenuState?
    /// A dismissed (Esc) "/" stays dismissed until the caret leaves it.
    @ObservationIgnored private var dismissedSlash: (blockID: UUID, location: Int)?
    /// Keeps the formatting bar visible without a selection (toolbar toggle).
    public var showsFormattingBar = false
    public var linkError: String?

    @ObservationIgnored private let repository: NoteRepository
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let autosaveDelay: Duration
    @ObservationIgnored private let onSaved: (UUID) -> Void
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var history = EditHistory()
    /// Updated on every caret move; not observed to avoid re-rendering per keystroke.
    @ObservationIgnored private(set) var selection: BlockSelection?

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

    /// Font preset shared by the selection (or the caret's run), for menu check marks.
    public var selectionFontFamily: FontFamilyPreset? {
        selectionRuns.map(\.fontFamily).allEqual ?? nil
    }

    public var selectionFontSize: FontSizePreset? {
        selectionRuns.map(\.fontSize).allEqual ?? nil
    }

    private var selectionRuns: [TextRun] {
        guard let selection, let block = note.blocks.first(where: { $0.id == selection.blockID }) else { return [] }
        let range = selection.range.isEmpty ? 0..<block.content.utf16Length : selection.range
        return block.content.split(atUTF16Offset: range.lowerBound).tail.split(atUTF16Offset: range.count).head.runs
    }

    public var activeBlock: NoteBlock? {
        activeBlockID.flatMap { id in note.blocks.first { $0.id == id } }
    }

    // MARK: Text edits

    public func setTitle(_ title: String) {
        guard title != note.title else { return }
        note.title = title
        markChanged()
    }

    /// Typing inside one block. Consecutive typing is one undo step.
    public func setContent(_ content: RichText, ofBlock id: UUID) {
        guard let index = index(of: id), note.blocks[index].content != content else { return }
        recordUndo(.typing(blockID: id))
        note.blocks[index].content = content
        markChanged()
    }

    /// Called by the text view whenever the caret or selection changes.
    public func updateSelection(blockID: UUID, range: Range<Int>) {
        let newSelection = BlockSelection(blockID: blockID, range: range)
        if let selection, selection.blockID != blockID || abs(selection.range.lowerBound - range.lowerBound) > 1 {
            history.breakCoalescing() // caret jumped: start a new undo step
        }
        selection = newSelection
        if activeBlockID != blockID { activeBlockID = blockID }
        let hasSelection = !range.isEmpty
        if hasTextSelection != hasSelection { hasTextSelection = hasSelection }
        let marks = index(of: blockID).map { note.blocks[$0].content.commonMarks(in: range) } ?? []
        if selectionMarks != marks { selectionMarks = marks }
    }

    // MARK: Inline formatting

    /// Toggles `mark` on a non-empty range. (Empty selections change typing
    /// attributes in the text view instead.)
    public func toggleMark(_ mark: InlineMark, blockID: UUID, range: Range<Int>) {
        guard !range.isEmpty else { return }
        transformContent(of: blockID, keepingSelection: range) { $0.toggling(mark, in: range) }
    }

    /// Font family preset. With no selection, applies to the whole block.
    public func setFontFamily(_ family: FontFamilyPreset?) {
        guard let (id, range) = formattingTarget() else { return }
        transformContent(of: id, keepingSelection: selection?.range) { $0.transformingRuns(in: range) { $0.fontFamily = family } }
    }

    /// Text size preset. With no selection, applies to the whole block.
    public func setFontSize(_ size: FontSizePreset?) {
        guard let (id, range) = formattingTarget() else { return }
        transformContent(of: id, keepingSelection: selection?.range) { $0.transformingRuns(in: range) { $0.fontSize = size } }
    }

    // MARK: Links

    public func beginLinkEditing(blockID: UUID, range: Range<Int>) {
        guard let index = index(of: blockID) else { return }
        let existing = note.blocks[index].content.commonLink(in: range)
        linkError = nil
        linkDraft = LinkDraft(blockID: blockID, range: range, url: existing?.absoluteString ?? "", hasExistingLink: existing != nil)
    }

    /// Applies the draft. Returns false (and sets `linkError`) for invalid or unsafe URLs.
    @discardableResult
    public func commitLink() -> Bool {
        guard let draft = linkDraft else { return false }
        guard let url = LinkValidator.validated(draft.url) else {
            linkError = "Enter a web address (https://…) or an email address."
            return false
        }
        linkDraft = nil
        linkError = nil
        if draft.range.isEmpty {
            // No selection: insert the address itself as linked text.
            let text = RichText(runs: [TextRun(url.absoluteString, link: url)])
            let end = draft.range.lowerBound + text.utf16Length
            transformContent(of: draft.blockID, keepingSelection: end..<end) { $0.replacing(draft.range, with: text) }
        } else {
            transformContent(of: draft.blockID, keepingSelection: draft.range) { $0.transformingRuns(in: draft.range) { $0.link = url } }
        }
        return true
    }

    public func removeLink() {
        guard let draft = linkDraft else { return }
        linkDraft = nil
        transformContent(of: draft.blockID, keepingSelection: draft.range) { $0.transformingRuns(in: draft.range) { $0.link = nil } }
    }

    public func cancelLinkEditing() {
        linkDraft = nil
        linkError = nil
        if let selection { focus(selection.blockID, offset: selection.range.lowerBound, length: selection.range.count) }
    }

    // MARK: Block commands

    public func toggleChecked(_ id: UUID) {
        guard let index = index(of: id), note.blocks[index].type == .checklistItem else { return }
        recordUndo(.structural)
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

    public func setBlockType(_ type: BlockType, blockID: UUID? = nil) {
        guard let id = blockID ?? activeBlockID else { return }
        applyKeepingCaret(on: id) { BlockEditing.setType($0, blockID: id, to: type) }
    }

    /// Tab (+1) / Shift+Tab (-1). Returns false for blocks that can't indent.
    @discardableResult
    public func indentBlock(_ id: UUID, by delta: Int) -> Bool {
        applyKeepingCaret(on: id) { BlockEditing.indent($0, blockID: id, by: delta) }
    }

    /// Move Up (-1) / Move Down (+1); keeps the caret in the moved block.
    @discardableResult
    public func moveBlock(_ id: UUID? = nil, by offset: Int) -> Bool {
        guard let id = id ?? activeBlockID else { return false }
        return applyKeepingCaret(on: id) { BlockEditing.move($0, blockID: id, by: offset) }
    }

    /// Drag and drop.
    public func moveBlock(_ id: UUID, relativeTo targetID: UUID, placeAfter: Bool) {
        applyKeepingCaret(on: id) { BlockEditing.move($0, blockID: id, relativeTo: targetID, placeAfter: placeAfter) }
    }

    public func paste(_ paragraphs: [PastedParagraph], blockID: UUID, range: Range<Int>) {
        apply { try BlockEditing.paste($0, blockID: blockID, range: range, paragraphs: paragraphs) }
    }

    // MARK: Slash commands

    /// Called by the text view after each edit or caret move with the "/query"
    /// at the caret (if any) and where it is on screen.
    public func updateSlashToken(_ token: SlashTrigger.Token?, blockID: UUID, anchor: CGRect?) {
        guard let token else {
            if slashMenu?.blockID == blockID { slashMenu = nil }
            if dismissedSlash?.blockID == blockID { dismissedSlash = nil }
            return
        }
        if let dismissed = dismissedSlash, dismissed.blockID == blockID, dismissed.location == token.range.lowerBound {
            return
        }
        let commands = SlashCommand.matches(token.query)
        guard !commands.isEmpty else {
            slashMenu = nil
            return
        }
        let keepHighlight = slashMenu?.blockID == blockID && slashMenu?.query == token.query
        slashMenu = SlashMenuState(
            blockID: blockID, range: token.range, query: token.query, commands: commands,
            highlighted: keepHighlight ? min(slashMenu?.highlighted ?? 0, commands.count - 1) : 0,
            anchor: anchor ?? slashMenu?.anchor
        )
    }

    public var isSlashMenuOpen: Bool { slashMenu != nil }

    public func moveSlashHighlight(by delta: Int) {
        guard var menu = slashMenu, !menu.commands.isEmpty else { return }
        menu.highlighted = (menu.highlighted + delta + menu.commands.count) % menu.commands.count
        slashMenu = menu
    }

    /// Return/Tab in the menu, or a click on a command.
    public func applySlashCommand(_ command: SlashCommand? = nil) {
        guard let menu = slashMenu else { return }
        let chosen = command ?? menu.commands[menu.highlighted]
        slashMenu = nil
        apply { try BlockEditing.applySlashCommand($0, blockID: menu.blockID, removing: menu.range, type: chosen.type) }
    }

    /// "/name " typed in full: apply without the menu.
    public func applyCompletedSlashCommand(_ command: SlashCommand, blockID: UUID, removing range: Range<Int>) {
        slashMenu = nil
        apply { try BlockEditing.applySlashCommand($0, blockID: blockID, removing: range, type: command.type) }
    }

    /// Esc: closes the menu and leaves the typed text as it is.
    public func dismissSlashMenu() {
        guard let menu = slashMenu else { return }
        dismissedSlash = (menu.blockID, menu.range.lowerBound)
        slashMenu = nil
    }

    // MARK: Undo

    public func undo() {
        guard let snapshot = history.undo(current: currentSnapshot()) else { return }
        restore(snapshot)
    }

    public func redo() {
        guard let snapshot = history.redo(current: currentSnapshot()) else { return }
        restore(snapshot)
    }

    // MARK: Focus

    public func focus(_ id: UUID, offset: Int, length: Int = 0, scrollsIntoView: Bool = true) {
        focusRequest = FocusRequest(blockID: id, offset: offset, length: length, scrollsIntoView: scrollsIntoView)
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

    private func currentSnapshot() -> EditHistory.Snapshot {
        EditHistory.Snapshot(
            blocks: note.blocks,
            caret: selection.map { EditHistory.Caret(blockID: $0.blockID, offset: $0.range.lowerBound) }
        )
    }

    private func recordUndo(_ kind: EditHistory.Kind) {
        history.record(before: currentSnapshot(), kind: kind, at: now())
        syncUndoState()
    }

    private func syncUndoState() {
        if canUndo != history.canUndo { canUndo = history.canUndo }
        if canRedo != history.canRedo { canRedo = history.canRedo }
    }

    private func restore(_ snapshot: EditHistory.Snapshot) {
        note.blocks = snapshot.blocks
        markChanged()
        syncUndoState()
        if let caret = snapshot.caret, index(of: caret.blockID) != nil {
            focus(caret.blockID, offset: caret.offset)
        } else {
            focusFirstBlock()
        }
    }

    /// Block + range for preset formatting: the selection, or the whole active block.
    private func formattingTarget() -> (UUID, Range<Int>)? {
        guard let selection, let index = index(of: selection.blockID) else { return nil }
        let range = selection.range.isEmpty ? 0..<note.blocks[index].content.utf16Length : selection.range
        return (selection.blockID, range)
    }

    private func transformContent(of id: UUID, keepingSelection range: Range<Int>?, _ transform: (RichText) -> RichText) {
        guard let index = index(of: id) else { return }
        let updated = transform(note.blocks[index].content)
        guard updated != note.blocks[index].content else { return }
        recordUndo(.structural)
        note.blocks[index].content = updated
        markChanged()
        if let range { focus(id, offset: range.lowerBound, length: range.count, scrollsIntoView: false) }
        updateSelection(blockID: id, range: range ?? 0..<0)
    }

    private func apply(_ operation: (Note) throws -> BlockEditing.Result?) {
        do {
            guard let result = try operation(note) else { return }
            recordUndo(.structural)
            note = BlockEditing.normalizingRanks(result.note)
            markChanged()
            focus(result.focusBlockID, offset: result.focusOffset)
        } catch {
            Log.app.error("Block operation failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Applies a block-level change and puts the caret back where it was.
    @discardableResult
    private func applyKeepingCaret(on id: UUID, _ operation: (Note) -> Note?) -> Bool {
        guard let updated = operation(note) else { return false }
        recordUndo(.structural)
        note = BlockEditing.normalizingRanks(updated)
        markChanged()
        let range = (selection?.blockID == id ? selection?.range : nil) ?? 0..<0
        focus(id, offset: range.lowerBound, length: range.count)
        return true
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

private extension Array where Element: Equatable {
    /// The common element if all elements are equal; nil if empty or mixed.
    var allEqual: Element? {
        guard let first, allSatisfy({ $0 == first }) else { return nil }
        return first
    }
}

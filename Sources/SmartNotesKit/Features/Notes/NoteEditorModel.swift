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
    /// The caret goes into the block's nested text instead of its main text.
    public var isDetail: Bool
    public var token = UUID()

    /// Use `Int.max` to place the caret at the end of the block.
    public init(blockID: UUID, offset: Int, length: Int = 0, scrollsIntoView: Bool = true, isDetail: Bool = false) {
        self.blockID = blockID
        self.offset = offset
        self.length = length
        self.scrollsIntoView = scrollsIntoView
        self.isDetail = isDetail
    }
}

/// The current text selection inside one block (UTF-16 range).
public struct BlockSelection: Equatable, Sendable {
    public var blockID: UUID
    public var range: Range<Int>
    /// The selection is in the block's nested text.
    public var isDetail = false
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

/// Asks a block's tag control to open its picker (e.g. from "/custom").
public struct TagPickerRequest: Equatable, Sendable {
    public var blockID: UUID
    public var token = UUID()
}

/// State for the ⌘K link sheet.
public struct LinkDraft: Equatable, Sendable {
    public var blockID: UUID
    public var range: Range<Int>
    public var url: String
    public var hasExistingLink: Bool
    /// The link is in the block's nested text.
    public var isDetail = false
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
    /// Text selected across several blocks (nil when the selection is inside one block).
    public private(set) var rangeSelection: BlockRangeSelection?
    public var linkDraft: LinkDraft?
    public var tagPickerRequest: TagPickerRequest?
    public private(set) var slashMenu: SlashMenuState?
    /// Blocks whose nested text is shown. Not saved: notes open collapsed.
    public private(set) var expandedDetails: Set<UUID> = []
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
    /// Checked rows move to the bottom of their list (a preference, see `NotesModel`).
    @ObservationIgnored public var movesCheckedRowsDown = true
    /// The row whose menu is open (right click): it's shown selected.
    public private(set) var menuRowID: UUID?
    /// Asks the user for picture files (an open panel); set by the editor view.
    @ObservationIgnored public var imagePicker: (@MainActor () async -> [NoteImage])?
    /// Reads page titles for pasted links named after their address; nil reads none.
    @ObservationIgnored public var linkTitles: (any LinkTitleFetching)?

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
        if let rangeSelection {
            return BlockEditing.copiedParagraphs(note, selection: rangeSelection).flatMap(\.content.runs)
        }
        guard let selection, let block = note.blocks.first(where: { $0.id == selection.blockID }) else { return [] }
        let text = selection.isDetail ? block.detail : block.content
        let range = selection.range.isEmpty ? 0..<text.utf16Length : selection.range
        return text.split(atUTF16Offset: range.lowerBound).tail.split(atUTF16Offset: range.count).head.runs
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
        // A multi-block selection owns the toolbar state until it is cleared.
        guard rangeSelection == nil else { return }
        if activeBlockID != blockID { activeBlockID = blockID }
        let hasSelection = !range.isEmpty
        if hasTextSelection != hasSelection { hasTextSelection = hasSelection }
        let marks = index(of: blockID).map { note.blocks[$0].content.commonMarks(in: range) } ?? []
        if selectionMarks != marks { selectionMarks = marks }
    }

    // MARK: Inline formatting

    /// Toggles `mark` on a non-empty range. (Empty selections change typing
    /// attributes in the text view instead.)
    public func toggleMark(_ mark: InlineMark, blockID: UUID, range: Range<Int>, inDetail: Bool = false) {
        if rangeSelection != nil, !inDetail {
            toggleMarkInRangeSelection(mark)
            return
        }
        guard !range.isEmpty else { return }
        transformContent(of: blockID, inDetail: inDetail, keepingSelection: range) { $0.toggling(mark, in: range) }
    }

    /// Font family preset. With no selection, applies to the whole block.
    public func setFontFamily(_ family: FontFamilyPreset?) {
        if rangeSelection != nil { return transformRangeSelection { $0.fontFamily = family } }
        guard let (id, range, inDetail) = formattingTarget() else { return }
        transformContent(of: id, inDetail: inDetail, keepingSelection: selection?.range) { $0.transformingRuns(in: range) { $0.fontFamily = family } }
    }

    /// Text size preset. With no selection, applies to the whole block.
    public func setFontSize(_ size: FontSizePreset?) {
        if rangeSelection != nil { return transformRangeSelection { $0.fontSize = size } }
        guard let (id, range, inDetail) = formattingTarget() else { return }
        transformContent(of: id, inDetail: inDetail, keepingSelection: selection?.range) { $0.transformingRuns(in: range) { $0.fontSize = size } }
    }

    // MARK: Links

    public func beginLinkEditing(blockID: UUID, range: Range<Int>, inDetail: Bool = false) {
        guard let index = index(of: blockID) else { return }
        let text = inDetail ? note.blocks[index].detail : note.blocks[index].content
        let existing = text.commonLink(in: range)
        linkError = nil
        linkDraft = LinkDraft(blockID: blockID, range: range, url: existing?.absoluteString ?? "", hasExistingLink: existing != nil,
                              isDetail: inDetail)
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
            transformContent(of: draft.blockID, inDetail: draft.isDetail, keepingSelection: end..<end) { $0.replacing(draft.range, with: text) }
        } else {
            transformContent(of: draft.blockID, inDetail: draft.isDetail, keepingSelection: draft.range) {
                $0.transformingRuns(in: draft.range) { $0.link = url }
            }
        }
        return true
    }

    public func removeLink() {
        guard let draft = linkDraft else { return }
        linkDraft = nil
        transformContent(of: draft.blockID, inDetail: draft.isDetail, keepingSelection: draft.range) {
            $0.transformingRuns(in: draft.range) { $0.link = nil }
        }
    }

    public func cancelLinkEditing() {
        linkDraft = nil
        linkError = nil
        if let selection {
            focus(selection.blockID, offset: selection.range.lowerBound, length: selection.range.count, isDetail: selection.isDetail)
        }
    }

    // MARK: Block commands

    /// Checking a row also moves it below its list's open rows (unchecking
    /// brings it back up) when `movesCheckedRowsDown` is on. One undo step.
    public func toggleChecked(_ id: UUID) {
        guard let index = index(of: id), note.blocks[index].type == .checklistItem else { return }
        recordUndo(.structural)
        note.blocks[index].isChecked.toggle()
        if movesCheckedRowsDown, let settled = BlockEditing.settlingChecked(note, blockID: id) { note = settled }
        markChanged()
    }

    /// Sorts the note's lists, or only the selected rows when several are selected.
    public func sortRows(by order: RowSortOrder, reversed: Bool = false) {
        let scope = rangeSelection.map { Set(BlockEditing.segments(of: $0, in: note).map(\.blockID)) }
        guard let sorted = BlockEditing.sortRows(note, by: order, reversed: reversed, within: scope) else { return }
        recordUndo(.structural)
        note = sorted
        rangeSelection = nil
        markChanged()
        if let id = activeBlockID { refocusBlock(id) }
    }

    /// Sets or clears (`nil`) a block's tag. Defaults to the block with the caret.
    public func setBlockTag(_ tag: BlockTag?, blockID: UUID? = nil) {
        guard let id = blockID ?? activeBlockID else { return }
        // Choosing the tag the block already has still returns the caret to it.
        if !applyKeepingCaret(on: id, { BlockEditing.setTag($0, blockID: id, to: tag) }) { refocusBlock(id) }
    }

    /// Opens the tag picker next to the block.
    public func requestTagPicker(blockID: UUID? = nil) {
        guard let id = blockID ?? activeBlockID, index(of: id) != nil else { return }
        tagPickerRequest = TagPickerRequest(blockID: id)
    }

    /// Custom tags already used in this note, most used first, for quick reuse.
    public var customTagSuggestions: [String] {
        var counts: [String: Int] = [:]
        for block in note.blocks {
            if case .custom(let name)? = block.tag { counts[name, default: 0] += 1 }
        }
        return counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key.localizedCompare($1.key) == .orderedAscending }.map(\.key)
    }

    /// Puts the caret back in the block (e.g. after closing the tag picker).
    public func refocusBlock(_ id: UUID) {
        let current = selection?.blockID == id ? selection : nil
        let range = current?.range ?? 0..<0
        focus(id, offset: range.lowerBound, length: range.count, isDetail: current?.isDetail ?? false)
    }

    // MARK: Nested text

    public func isDetailExpanded(_ id: UUID) -> Bool {
        expandedDetails.contains(id)
    }

    /// The disclosure button: shows or hides a block's nested text. Showing a
    /// block without any puts the caret in it, ready to write.
    public func toggleDetail(_ id: UUID) {
        guard let index = index(of: id) else { return }
        if expandedDetails.contains(id) {
            collapseDetail(id)
        } else {
            expandedDetails.insert(id)
            if note.blocks[index].detail.isEmpty { focus(id, offset: 0, isDetail: true) }
        }
    }

    /// Format ▸ Nested Text (⌥⌘N): from a block, opens its nested text and puts
    /// the caret there; from inside the nested text, hides it and goes back.
    public func toggleNestedText() {
        guard let id = activeBlockID, let index = index(of: id) else { return }
        if selection?.blockID == id, selection?.isDetail == true {
            collapseDetail(id)
        } else {
            expandedDetails.insert(id)
            focus(id, offset: note.blocks[index].detail.utf16Length, isDetail: true)
        }
    }

    /// Hides a block's nested text; a caret inside it moves to the end of the block.
    public func collapseDetail(_ id: UUID) {
        guard expandedDetails.remove(id) != nil else { return }
        if selection?.blockID == id, selection?.isDetail == true, let index = index(of: id) {
            selection = BlockSelection(blockID: id, range: note.blocks[index].content.utf16Length..<note.blocks[index].content.utf16Length)
            focus(id, offset: .max)
        }
    }

    /// Typing in a block's nested text. Consecutive typing is one undo step.
    public func setDetail(_ detail: RichText, ofBlock id: UUID) {
        guard let index = index(of: id), note.blocks[index].detail != detail else { return }
        recordUndo(.typingDetail(blockID: id))
        note.blocks[index].detail = detail
        markChanged()
    }

    /// Deletes a block's nested text (undoable) and returns the caret to the block.
    public func removeDetail(_ id: UUID) {
        guard let index = index(of: id) else { return }
        expandedDetails.remove(id)
        if let updated = BlockEditing.setDetail(note, blockID: id, to: .empty) {
            recordUndo(.structural)
            note = updated
            markChanged()
        }
        focus(id, offset: note.blocks[index].content.utf16Length)
    }

    /// Caret or selection moved inside a block's nested text.
    public func updateDetailSelection(blockID: UUID, range: Range<Int>) {
        let newSelection = BlockSelection(blockID: blockID, range: range, isDetail: true)
        if let selection, selection.blockID != blockID || !selection.isDetail || abs(selection.range.lowerBound - range.lowerBound) > 1 {
            history.breakCoalescing()
        }
        selection = newSelection
        guard rangeSelection == nil else { return }
        if activeBlockID != blockID { activeBlockID = blockID }
        if hasTextSelection != !range.isEmpty { hasTextSelection = !range.isEmpty }
        let marks = index(of: blockID).map { note.blocks[$0].detail.commonMarks(in: range) } ?? []
        if selectionMarks != marks { selectionMarks = marks }
    }

    /// Paste inside nested text: everything stays in it, one line per paragraph.
    public func pasteIntoDetail(_ paragraphs: [PastedParagraph], blockID: UUID, range: Range<Int>) {
        guard let index = index(of: blockID), !paragraphs.isEmpty else { return }
        let inserted = BlockEditing.nestedText(from: paragraphs)
        let detail = note.blocks[index].detail.replacing(range, with: inserted)
        guard let updated = BlockEditing.setDetail(note, blockID: blockID, to: detail) else { return }
        recordUndo(.structural)
        note = updated
        markChanged()
        focus(blockID, offset: range.lowerBound + inserted.utf16Length, isDetail: true)
        nameLinks(in: paragraphs)
    }

    /// Backspace at the start of nested text: empty nested text closes, and the
    /// caret returns to the end of the block. Returns false when nothing happened.
    @discardableResult
    public func backspaceAtDetailStart(_ id: UUID) -> Bool {
        guard let index = index(of: id), note.blocks[index].detail.isEmpty else { return false }
        collapseDetail(id)
        focus(id, offset: .max)
        return true
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
        if blockID == nil, let selection = rangeSelection {
            // Every block the selection touches changes kind; the selection stays.
            let ids = BlockEditing.segments(of: selection, in: note).map(\.blockID)
            let updated = ids.reduce(note) { note, id in BlockEditing.setType(note, blockID: id, to: type) ?? note }
            guard updated != note else { return }
            recordUndo(.structural)
            note = updated
            markChanged()
            return
        }
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

    /// Dropped onto another row: the block becomes hidden nested text of that
    /// row, which stays collapsed. The caret goes to the end of that row.
    public func nestBlock(_ id: UUID, into targetID: UUID) {
        guard let updated = BlockEditing.nest(note, blockID: id, into: targetID) else { return }
        recordUndo(.structural)
        note = updated
        expandedDetails.remove(id)
        if rangeSelection.map({ [$0.anchor.blockID, $0.focus.blockID].contains(id) }) == true { rangeSelection = nil }
        markChanged()
        focus(targetID, offset: .max)
    }

    /// A nested row dragged out between rows: it becomes a block again, and the
    /// caret goes to its end.
    public func unnestRow(_ row: Range<Int>, of id: UUID, relativeTo targetID: UUID, placeAfter: Bool) {
        guard let result = BlockEditing.unnest(note, blockID: id, row: row, relativeTo: targetID, placeAfter: placeAfter) else { return }
        recordUndo(.structural)
        note = BlockEditing.normalizingRanks(result.note)
        finishMovingNestedRow(from: id)
        focus(result.focusBlockID, offset: result.focusOffset)
    }

    /// A nested row dragged onto another row: it moves into that row's nested
    /// text, which stays collapsed.
    public func moveNestedRow(_ row: Range<Int>, of id: UUID, into targetID: UUID) {
        guard let updated = BlockEditing.moveNestedRow(note, blockID: id, row: row, into: targetID) else { return }
        recordUndo(.structural)
        note = updated
        finishMovingNestedRow(from: id)
        focus(targetID, offset: .max)
    }

    // MARK: Columns

    /// Format ▸ Move to Right / Left Column: the block with the caret, or every
    /// block of a multi-block selection, goes to the end of that column. The
    /// first move right starts the right column; emptying the left one ends it.
    public func moveSelection(toColumn column: Int) {
        let ids = rangeSelection.map { BlockEditing.segments(of: $0, in: note).map(\.blockID) } ?? activeBlockID.map { [$0] } ?? []
        moveBlocks(ids, toColumn: column)
    }

    /// A block dragged beside the note, or into the other column's empty space.
    public func moveBlocks(_ ids: [UUID], toColumn column: Int) {
        guard let updated = BlockEditing.moveToColumn(note, blockIDs: ids, column: column) else { return }
        recordUndo(.structural)
        note = updated
        rangeSelection = nil
        markChanged()
        if let id = activeBlockID, ids.contains(id) { refocusBlock(id) } else if let id = ids.last { focus(id, offset: .max) }
    }

    // MARK: Row tools

    public func setMenuRow(_ id: UUID?) {
        if menuRowID != id { menuRowID = id }
    }

    /// The row menu's Duplicate (⇧⌘D): a copy right below; the caret goes to its end.
    public func duplicateBlock(_ id: UUID? = nil) {
        guard let id = id ?? activeBlockID else { return }
        apply { BlockEditing.duplicate($0, blockID: id) }
    }

    /// ⌥-drag: a copy dropped before or after another row (the original stays).
    public func duplicateBlock(_ id: UUID, relativeTo targetID: UUID, placeAfter: Bool) {
        apply { BlockEditing.duplicate($0, blockID: id, relativeTo: targetID, placeAfter: placeAfter) }
    }

    /// ⌥-drag beside the note: a copy starts (or ends) that column.
    public func duplicateBlock(_ id: UUID, toColumn column: Int) {
        apply { BlockEditing.duplicate($0, blockID: id, toColumn: column) }
    }

    /// Copy Row: whole blocks, with their kind, tag, nested text and picture.
    public func paragraphs(ofBlocks ids: [UUID]) -> [PastedParagraph] {
        BlockEditing.paragraphs(of: note, blockIDs: ids)
    }

    // MARK: Pictures

    /// Pictures dropped or pasted at a block go in before or after it (taking
    /// its place when it is an empty line). The caret goes to the last caption.
    @discardableResult
    public func insertImages(_ images: [NoteImage], relativeTo targetID: UUID, placeAfter: Bool) -> Bool {
        var inserted = false
        apply { note in
            let result = BlockEditing.insertImages(note, images, relativeTo: targetID, placeAfter: placeAfter)
            inserted = result != nil
            return result
        }
        return inserted
    }

    /// Pictures dropped beside a one-column note start its right column.
    @discardableResult
    public func insertImagesInNewColumn(_ images: [NoteImage]) -> Bool {
        var inserted = false
        apply { note in
            let result = BlockEditing.insertImagesInNewColumn(note, images)
            inserted = result != nil
            return result
        }
        return inserted
    }

    /// Format ▸ Insert Image… and "/image": asks for pictures, then puts them
    /// in below the block with the caret.
    public func chooseImages(for blockID: UUID? = nil) {
        guard let picker = imagePicker, let id = blockID ?? activeBlockID ?? note.blocks.last?.id else { return }
        Task { [weak self] in
            let images = await picker()
            guard let self, !images.isEmpty else { return }
            self.insertImages(images, relativeTo: self.index(of: id) != nil ? id : (self.note.blocks.last?.id ?? id), placeAfter: true)
        }
    }

    /// A picture resized by its corner (one undo step per drag); nil goes
    /// back to its own size.
    public func setImageWidth(_ width: Double?, of id: UUID) {
        guard let updated = BlockEditing.setImageWidth(note, blockID: id, to: width) else { return }
        recordUndo(.structural)
        note = updated
        markChanged()
    }

    /// The picture's delete button: an image block goes; a row keeps its text
    /// and loses its attached picture. Undoable.
    public func deleteImage(of id: UUID) {
        guard let index = index(of: id) else { return }
        if note.blocks[index].type == .image { return deleteBlock(id) }
        guard let updated = BlockEditing.removeAttachedImage(note, from: id) else { return }
        recordUndo(.structural)
        note = updated
        markChanged()
    }

    /// A row's picture dragged out between rows becomes an image block there.
    public func detachImage(from rowID: UUID, relativeTo targetID: UUID, placeAfter: Bool) {
        apply { BlockEditing.detachImage($0, from: rowID, relativeTo: targetID, placeAfter: placeAfter) }
    }

    /// A row's picture dragged onto another row.
    public func moveAttachedImage(from rowID: UUID, to targetID: UUID) {
        guard let updated = BlockEditing.moveAttachedImage(note, from: rowID, to: targetID) else { return }
        recordUndo(.structural)
        note = updated
        markChanged()
    }

    /// Deletes a block, e.g. a picture from its delete button. Undoable.
    public func deleteBlock(_ id: UUID) {
        expandedDetails.remove(id)
        if rangeSelection.map({ [$0.anchor.blockID, $0.focus.blockID].contains(id) }) == true { rangeSelection = nil }
        apply { BlockEditing.removing($0, blockID: id) }
    }

    private func finishMovingNestedRow(from id: UUID) {
        if index(of: id).map({ note.blocks[$0].detail.isEmpty }) == true { expandedDetails.remove(id) }
        rangeSelection = nil
        markChanged()
    }

    public func paste(_ paragraphs: [PastedParagraph], blockID: UUID, range: Range<Int>) {
        apply { try BlockEditing.paste($0, blockID: blockID, range: range, paragraphs: paragraphs) }
        nameLinks(in: paragraphs)
    }

    // MARK: Link names

    /// Pasted links still named after their address get their page's title
    /// once it arrives (see `LinkTitleFetching`). Not an undo step of its own:
    /// undoing the paste takes the link away, title and all.
    private func nameLinks(in paragraphs: [PastedParagraph]) {
        guard let linkTitles else { return }
        var asked = Set<URL>()
        for run in paragraphs.flatMap(\.content.runs) {
            guard let url = run.link, run.text == LinkNaming.readableName(for: url),
                  LinkNaming.mayFetchTitle(for: url), asked.insert(url).inserted else { continue }
            let name = run.text
            Task { [weak self] in
                guard let title = await linkTitles.title(for: url) else { return }
                self?.renameLinks(to: url, from: name, to: title)
            }
        }
    }

    /// Every link to `url` whose text is still `name` now reads `title`; the
    /// caret stays by the same character.
    func renameLinks(to url: URL, from name: String, to title: String) {
        guard name != title else { return }
        var changed = false
        for index in note.blocks.indices {
            for inDetail in [false, true] {
                let text = inDetail ? note.blocks[index].detail : note.blocks[index].content
                var shift = 0
                var offset = 0
                let caret = selection.flatMap { $0.blockID == note.blocks[index].id && $0.isDetail == inDetail ? $0.range : nil }
                let runs = text.runs.map { run -> TextRun in
                    defer { offset += run.text.utf16.count }
                    guard run.link == url, run.text == name else { return run }
                    var renamed = run
                    renamed.text = title
                    if let caret, offset + run.text.utf16.count <= caret.lowerBound {
                        shift += title.utf16.count - run.text.utf16.count
                    }
                    return renamed
                }
                guard runs != text.runs else { continue }
                changed = true
                if inDetail { note.blocks[index].detail = RichText(runs: runs) } else { note.blocks[index].content = RichText(runs: runs) }
                if let caret {
                    focus(note.blocks[index].id, offset: caret.lowerBound + shift, length: caret.count, scrollsIntoView: false, isDetail: inDetail)
                }
            }
        }
        if changed { markChanged() }
    }

    // MARK: Multi-block selection

    /// Selects from `anchor` to `focus`. A selection inside one block is left to
    /// that block's text view, so this clears instead.
    public func setRangeSelection(anchor: BlockPosition, focus: BlockPosition) {
        let selection = BlockRangeSelection(anchor: anchor, focus: focus)
        guard anchor.blockID != focus.blockID, BlockEditing.ordered(selection, in: note) != nil else {
            clearRangeSelection()
            return
        }
        guard selection != rangeSelection else { return }
        rangeSelection = selection
        history.breakCoalescing()
        activeBlockID = focus.blockID
        if !hasTextSelection { hasTextSelection = true }
        refreshRangeSelectionMarks()
    }

    public func clearRangeSelection() {
        guard rangeSelection != nil else { return }
        rangeSelection = nil
        if let selection {
            activeBlockID = selection.blockID
            hasTextSelection = !selection.range.isEmpty
        } else {
            hasTextSelection = false
        }
    }

    /// ⌘A in a block that is already fully selected: the whole note.
    public func selectAllBlocks() {
        guard let first = note.blocks.first, let last = note.blocks.last, first.id != last.id else { return }
        setRangeSelection(anchor: BlockPosition(blockID: first.id, offset: 0),
                          focus: BlockPosition(blockID: last.id, offset: last.content.utf16Length))
    }

    /// The selected range in each block, top to bottom (empty without a multi-block selection).
    public var rangeSegments: [BlockSegment] {
        rangeSelection.map { BlockEditing.segments(of: $0, in: note) } ?? []
    }

    /// Copy: the selected paragraphs with their kinds.
    public var copiedRangeParagraphs: [PastedParagraph] {
        rangeSelection.map { BlockEditing.copiedParagraphs(note, selection: $0) } ?? []
    }

    /// Backspace / Delete / Cut.
    public func deleteRangeSelection() {
        guard let selection = rangeSelection else { return }
        rangeSelection = nil
        apply { try BlockEditing.deleteRange($0, selection: selection) }
    }

    /// Typing over the selection replaces it; Return (`"\n"`) also splits there.
    public func replaceRangeSelection(with text: String) {
        guard let selection = rangeSelection else { return }
        rangeSelection = nil
        apply { note in
            let deleted = try BlockEditing.deleteRange(note, selection: selection)
            if text == "\n" {
                return try BlockEditing.split(deleted.note, blockID: deleted.focusBlockID, atUTF16Offset: deleted.focusOffset)
            }
            // Typed text continues the formatting before the caret.
            let block = deleted.note.blocks.first { $0.id == deleted.focusBlockID }
            var run = block?.content.split(atUTF16Offset: deleted.focusOffset).head.runs.last ?? TextRun("")
            run.text = text
            run.link = nil
            let offset = deleted.focusOffset
            return try BlockEditing.paste(deleted.note, blockID: deleted.focusBlockID, range: offset..<offset,
                                          paragraphs: [PastedParagraph(content: RichText(runs: [run]))])
        }
    }

    /// Pasting over the selection replaces it.
    public func pasteOverRangeSelection(_ paragraphs: [PastedParagraph]) {
        guard let selection = rangeSelection else { return }
        rangeSelection = nil
        apply { note in
            let deleted = try BlockEditing.deleteRange(note, selection: selection)
            let offset = deleted.focusOffset
            return try BlockEditing.paste(deleted.note, blockID: deleted.focusBlockID, range: offset..<offset, paragraphs: paragraphs)
                ?? deleted
        }
        nameLinks(in: paragraphs)
    }

    private func toggleMarkInRangeSelection(_ mark: InlineMark) {
        let segments = rangeSegments.filter { !$0.range.isEmpty }
        guard !segments.isEmpty else { return }
        let allMarked = segments.allSatisfy { segment in
            note.blocks.first { $0.id == segment.blockID }?.content.commonMarks(in: segment.range).contains(mark) ?? false
        }
        transformRangeSelection { run in
            if allMarked { run.marks.remove(mark) } else { run.marks.insert(mark) }
        }
    }

    /// Applies `transform` to the selected runs of every covered block, as one undo step.
    private func transformRangeSelection(_ transform: (inout TextRun) -> Void) {
        var updated = note
        for segment in rangeSegments where !segment.range.isEmpty {
            guard let index = updated.blocks.firstIndex(where: { $0.id == segment.blockID }) else { continue }
            updated.blocks[index].content = updated.blocks[index].content.transformingRuns(in: segment.range, transform)
        }
        guard updated != note else { return }
        recordUndo(.structural)
        note = updated
        markChanged()
        refreshRangeSelectionMarks()
    }

    private func refreshRangeSelectionMarks() {
        let segments = rangeSegments.filter { !$0.range.isEmpty }
        let marks = segments.compactMap { segment in
            note.blocks.first { $0.id == segment.blockID }?.content.commonMarks(in: segment.range)
        }
        let common = marks.dropFirst().reduce(marks.first ?? []) { $0.intersection($1) }
        if selectionMarks != common { selectionMarks = common }
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
        // "Remove tag" only makes sense on a tagged block.
        let isTagged = index(of: blockID).map { note.blocks[$0].tag != nil } ?? false
        let commands = SlashCommand.matches(token.query).filter { isTagged || $0.action != .removeTag }
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

    /// The pointer moved over a command.
    public func highlightSlashCommand(at index: Int) {
        guard var menu = slashMenu, menu.commands.indices.contains(index), menu.highlighted != index else { return }
        menu.highlighted = index
        slashMenu = menu
    }

    /// Return/Tab in the menu, or a click on a command.
    public func applySlashCommand(_ command: SlashCommand? = nil) {
        guard let menu = slashMenu else { return }
        let chosen = command ?? menu.commands[menu.highlighted]
        slashMenu = nil
        runSlashCommand(chosen, blockID: menu.blockID, removing: menu.range)
    }

    /// "/name " typed in full: apply without the menu.
    public func applyCompletedSlashCommand(_ command: SlashCommand, blockID: UUID, removing range: Range<Int>) {
        slashMenu = nil
        runSlashCommand(command, blockID: blockID, removing: range)
    }

    private func runSlashCommand(_ command: SlashCommand, blockID: UUID, removing range: Range<Int>) {
        apply { try BlockEditing.applySlashCommand($0, blockID: blockID, removing: range, action: command.action) }
        if command.action == .customTag { requestTagPicker(blockID: blockID) }
        if command.action == .nestedText, let index = index(of: blockID) {
            focus(blockID, offset: note.blocks[index].detail.utf16Length, isDetail: true)
        }
        if command.action == .image { chooseImages(for: blockID) }
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

    public func focus(_ id: UUID, offset: Int, length: Int = 0, scrollsIntoView: Bool = true, isDetail: Bool = false) {
        if isDetail { expandedDetails.insert(id) }
        focusRequest = FocusRequest(blockID: id, offset: offset, length: length, scrollsIntoView: scrollsIntoView, isDetail: isDetail)
    }

    /// `scrollsIntoView: false` keeps the note scrolled to its top (title visible).
    public func focusFirstBlock(scrollsIntoView: Bool = true) {
        if let first = note.blocks.first { focus(first.id, offset: 0, scrollsIntoView: scrollsIntoView) }
    }

    /// The end of the last block, or of the last block of `column`.
    public func focusLastBlockEnd(column: Int? = nil) {
        let last = column.flatMap { column in note.blocks.last { $0.column == column } } ?? note.blocks.last
        if let last { focus(last.id, offset: .max) }
    }

    /// Moves the caret to the end of the previous block (into its nested text
    /// when that is shown). Returns false at the first block.
    @discardableResult
    public func focusPrevious(before id: UUID) -> Bool {
        guard let index = index(of: id), index > 0 else { return false }
        let previous = note.blocks[index - 1].id
        focus(previous, offset: .max, isDetail: expandedDetails.contains(previous))
        return true
    }

    /// Moves the caret to the start of the next block, or of this block's nested
    /// text when that is shown. Returns false at the end of the note.
    @discardableResult
    public func focusNext(after id: UUID, fromDetail: Bool = false) -> Bool {
        if !fromDetail, expandedDetails.contains(id), index(of: id) != nil {
            focus(id, offset: 0, isDetail: true)
            return true
        }
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
            caret: selection.map { EditHistory.Caret(blockID: $0.blockID, offset: $0.range.lowerBound, isDetail: $0.isDetail) }
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
        rangeSelection = nil
        note.blocks = snapshot.blocks
        markChanged()
        syncUndoState()
        if let caret = snapshot.caret, index(of: caret.blockID) != nil {
            focus(caret.blockID, offset: caret.offset, isDetail: caret.isDetail)
        } else {
            focusFirstBlock()
        }
    }

    /// Block + range for preset formatting: the selection, or the whole active
    /// block (or its whole nested text, when the caret is there).
    private func formattingTarget() -> (UUID, Range<Int>, inDetail: Bool)? {
        guard let selection, let index = index(of: selection.blockID) else { return nil }
        let text = selection.isDetail ? note.blocks[index].detail : note.blocks[index].content
        let range = selection.range.isEmpty ? 0..<text.utf16Length : selection.range
        return (selection.blockID, range, selection.isDetail)
    }

    private func transformContent(of id: UUID, inDetail: Bool = false, keepingSelection range: Range<Int>?, _ transform: (RichText) -> RichText) {
        guard let index = index(of: id) else { return }
        let current = inDetail ? note.blocks[index].detail : note.blocks[index].content
        let updated = transform(current)
        guard updated != current else { return }
        recordUndo(.structural)
        if inDetail { note.blocks[index].detail = updated } else { note.blocks[index].content = updated }
        markChanged()
        if let range { focus(id, offset: range.lowerBound, length: range.count, scrollsIntoView: false, isDetail: inDetail) }
        if inDetail {
            updateDetailSelection(blockID: id, range: range ?? 0..<0)
        } else {
            updateSelection(blockID: id, range: range ?? 0..<0)
        }
    }

    private func apply(_ operation: (Note) throws -> BlockEditing.Result?) {
        do {
            guard let result = try operation(note) else { return }
            // Only the caret moves (e.g. Backspace after a picture goes to its caption).
            guard result.note != note else { return focus(result.focusBlockID, offset: result.focusOffset) }
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
        let current = selection?.blockID == id ? selection : nil
        let range = current?.range ?? 0..<0
        focus(id, offset: range.lowerBound, length: range.count, isDetail: current?.isDetail ?? false)
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

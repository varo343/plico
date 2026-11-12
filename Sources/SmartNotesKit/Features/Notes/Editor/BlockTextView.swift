import AppKit
import SwiftUI

/// Callbacks from one block's text view to the editor model.
struct BlockTextActions {
    var onChange: (RichText) -> Void
    var onSelectionChange: (Range<Int>) -> Void
    /// Enter (without Shift) at the given caret offset.
    var onEnter: (Int) -> Void
    /// Backspace with the caret at offset 0. Return true if handled.
    var onBackspaceAtStart: () -> Bool
    /// Arrow keys at the block's edges. Return true if focus moved.
    var onExitUp: () -> Bool
    var onExitDown: () -> Bool
    /// Tab (+1) / Shift+Tab (-1). Return true if handled.
    var onIndent: (Int) -> Bool
    var onToggleMark: (InlineMark, Range<Int>) -> Void
    var onEditLink: (Range<Int>) -> Void
    var onPaste: ([PastedParagraph], Range<Int>) -> Void
    var onMoveBlock: (Int) -> Void
    var onUndo: () -> Void
    var onRedo: () -> Void
    var canUndo: () -> Bool
    var canRedo: () -> Bool
    /// "/query" at the caret changed (nil when there is none).
    var onSlashToken: (SlashTrigger.Token?, CGRect?) -> Void
    /// "/name " typed in full.
    var onSlashCompleted: (SlashCommand, Range<Int>) -> Void
    var isSlashMenuOpen: () -> Bool
    var onSlashMove: (Int) -> Void
    var onSlashConfirm: () -> Void
    var onSlashDismiss: () -> Void
    /// Pointer entered/left the text (SwiftUI hover doesn't fire over an NSTextView).
    var onHoverChange: (Bool) -> Void = { _ in }
    /// Context-menu entry for the block's nested text ("Add Nested Text"…); nil hides it.
    var nestedTextMenuTitle: String?
    var onNestedText: () -> Void = {}
    /// Pictures dragged over the text: whether they would go after the block
    /// (true) or before it; nil when the drag leaves.
    var onImageDragHover: (Bool?) -> Void = { _ in }
    /// Pictures dropped on the text (the image data, and after the block or before it).
    var onImageDrop: ([Data], Bool) -> Void = { _, _ in }
    /// A right click (or ⌃-click) on the text opens the row menu (see
    /// `RowMenu`); nil keeps the standard text menu (nested text).
    var showRowMenu: ((NSEvent, NSTextView) -> Void)?
}

/// Where one row of nested text starts, in its text view's coordinates.
struct NestedRowFrame: Equatable {
    var range: Range<Int>
    var frame: CGRect
}

/// One logical block's text, edited by a TextKit 1 NSTextView. Each block is
/// its own text view so blocks can be dragged and reordered as units.
struct BlockTextView: NSViewRepresentable {
    let content: RichText
    let style: BlockTextStyle
    let accessibilityLabel: String
    let focusRequest: FocusRequest?
    let blockID: UUID
    let actions: BlockTextActions
    /// Shared by the note's blocks for selections that span several of them.
    var tracker: BlockSelectionTracker?
    /// This block's part of a multi-block selection, if any.
    var rangeHighlight: Range<Int>?
    var isRangeSelecting = false
    /// Edits a block's nested text: Return adds a line instead of a new block.
    var isNestedText = false
    /// Nested text: where each draggable row starts, so a grip can sit beside it.
    var onRowFrames: (([NestedRowFrame]) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> BlockNSTextView {
        let view = BlockNSTextView()
        view.delegate = context.coordinator
        view.coordinator = context.coordinator
        context.coordinator.parent = self
        apply(to: view, coordinator: context.coordinator)
        view.blockID = blockID
        view.isNestedText = isNestedText
        view.onRowFrames = onRowFrames
        view.tracker = tracker
        tracker?.register(view, for: blockID)
        view.setRangeHighlight(rangeHighlight, isActive: isRangeSelecting)
        return view
    }

    func updateNSView(_ view: BlockNSTextView, context: Context) {
        context.coordinator.parent = self
        if content != context.coordinator.lastContent || style != context.coordinator.lastStyle {
            apply(to: view, coordinator: context.coordinator)
        }
        view.setAccessibilityLabel(accessibilityLabel)
        view.onRowFrames = onRowFrames
        if view.tracker !== tracker || view.blockID != blockID {
            view.blockID = blockID
            view.tracker = tracker
            tracker?.register(view, for: blockID)
        }
        view.setRangeHighlight(rangeHighlight, isActive: isRangeSelecting)
        if let request = focusRequest, request.blockID == blockID, request.isDetail == isNestedText,
           request.token != context.coordinator.handledFocusToken {
            context.coordinator.handledFocusToken = request.token
            view.focus(atUTF16Offset: request.offset, length: request.length, scrollsIntoView: request.scrollsIntoView)
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: BlockNSTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 480
        // The row's HStack asks how wide the text could grow: as wide as
        // offered. Its height there is never used, so the text isn't laid out
        // again for it (that was every second measurement while typing).
        if width.isInfinite { return CGSize(width: width, height: style.lineHeight) }
        return CGSize(width: width, height: nsView.height(forWidth: width, minimumLineHeight: style.lineHeight))
    }

    /// Programmatic content replacement (undo, formatting, structural edits).
    /// The selection is preserved where it still fits.
    private func apply(to view: BlockNSTextView, coordinator: Coordinator) {
        let selection = view.selectedRange()
        coordinator.isApplying = true
        view.textStorage?.setAttributedString(RichTextAttributes.attributedString(for: content, style: style))
        view.typingAttributes = RichTextAttributes.typingAttributes(style: style)
        let length = content.utf16Length
        if selection.location <= length {
            view.setSelectedRange(NSRange(location: selection.location, length: min(selection.length, length - selection.location)))
        }
        coordinator.isApplying = false
        coordinator.lastContent = content
        coordinator.lastStyle = style
        view.refreshRangeHighlight()
        view.invalidateIntrinsicContentSize()
        view.reportRowFrames()
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: BlockTextView?
        var lastContent: RichText?
        var lastStyle: BlockTextStyle?
        var handledFocusToken: UUID?
        var isApplying = false

        func textDidChange(_ notification: Notification) {
            guard !isApplying, let view = notification.object as? BlockNSTextView, let storage = view.textStorage else { return }
            let content = RichTextAttributes.richText(from: storage)
            lastContent = content
            view.invalidateIntrinsicContentSize()
            parent?.actions.onChange(content)
            view.reportRowFrames()
            let caret = view.selectedRange()
            if caret.length == 0, let (command, range) = SlashTrigger.completedCommand(in: view.string, caret: caret.location) {
                parent?.actions.onSlashCompleted(command, range)
            } else {
                reportSlashToken(in: view)
            }
        }

        /// Tells the model about the "/query" at the caret and where to show the menu.
        func reportSlashToken(in view: BlockNSTextView) {
            let caret = view.selectedRange()
            let token = caret.length == 0 ? SlashTrigger.token(in: view.string, caret: caret.location) : nil
            var anchor: CGRect?
            if let token {
                anchor = view.firstRect(forCharacterRange: NSRange(location: token.range.lowerBound, length: 0), actualRange: nil)
            }
            parent?.actions.onSlashToken(token, anchor)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isApplying, let view = notification.object as? BlockNSTextView, view.window?.firstResponder === view else { return }
            parent?.actions.onSelectionChange(view.selectedUTF16Range)
            reportSlashToken(in: view)
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard let parent, let view = textView as? BlockNSTextView else { return false }
            let selection = view.selectedRange()
            // While the slash menu is open, navigation keys drive the menu.
            if parent.actions.isSlashMenuOpen() {
                switch selector {
                case #selector(NSResponder.moveUp(_:)): parent.actions.onSlashMove(-1); return true
                case #selector(NSResponder.moveDown(_:)): parent.actions.onSlashMove(1); return true
                case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertTab(_:)):
                    parent.actions.onSlashConfirm(); return true
                case #selector(NSResponder.cancelOperation(_:)): parent.actions.onSlashDismiss(); return true
                default: break
                }
            }
            switch selector {
            case #selector(NSResponder.insertNewline(_:)) where parent.isNestedText:
                view.insertText("\n", replacementRange: selection)
                return true
            case #selector(NSResponder.insertNewline(_:)):
                // Shift+Return is handled in keyDown as a soft break.
                if selection.length > 0 {
                    view.insertText("", replacementRange: selection)
                }
                parent.actions.onEnter(selection.location)
                return true
            case #selector(NSResponder.deleteBackward(_:)):
                guard selection.location == 0, selection.length == 0 else { return false }
                return parent.actions.onBackspaceAtStart()
            case #selector(NSResponder.insertTab(_:)):
                return parent.actions.onIndent(1)
            case #selector(NSResponder.insertBacktab(_:)):
                return parent.actions.onIndent(-1)
            case #selector(NSResponder.moveUp(_:)):
                guard selection.length == 0, view.isCaretOnFirstLine else { return false }
                return parent.actions.onExitUp()
            case #selector(NSResponder.moveDown(_:)):
                guard selection.length == 0, view.isCaretOnLastLine else { return false }
                return parent.actions.onExitDown()
            case #selector(NSResponder.moveLeft(_:)):
                guard selection.location == 0, selection.length == 0 else { return false }
                return parent.actions.onExitUp()
            case #selector(NSResponder.moveRight(_:)):
                guard selection.length == 0, selection.location == view.string.utf16.count else { return false }
                return parent.actions.onExitDown()
            default:
                return false
            }
        }

        /// Only web and mail links open; anything else is ignored.
        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            let url = (link as? URL) ?? (link as? String).flatMap(URL.init(string:))
            if let url, LinkValidator.isAllowed(url) {
                NSWorkspace.shared.open(url)
            }
            return true
        }

        /// Adds block commands to the standard text context menu (nested text;
        /// a block's own text opens the row menu instead, see `rightMouseDown`).
        func textView(_ view: NSTextView, menu: NSMenu, for event: NSEvent, at charIndex: Int) -> NSMenu? {
            menu.addItem(.separator())
            let up = NSMenuItem(title: "Move Block Up", action: #selector(moveBlockUp), keyEquivalent: "")
            up.target = self
            let down = NSMenuItem(title: "Move Block Down", action: #selector(moveBlockDown), keyEquivalent: "")
            down.target = self
            menu.addItem(up)
            menu.addItem(down)
            if let title = parent?.actions.nestedTextMenuTitle {
                let nested = NSMenuItem(title: title, action: #selector(nestedText), keyEquivalent: "")
                nested.target = self
                menu.addItem(nested)
            }
            return menu
        }

        @objc func nestedText() { parent?.actions.onNestedText() }
        @objc func moveBlockUp() { parent?.actions.onMoveBlock(-1) }
        @objc func moveBlockDown() { parent?.actions.onMoveBlock(1) }
    }
}

/// NSTextView configured for a single block (TextKit 1 for predictable layout).
final class BlockNSTextView: NSTextView {
    weak var coordinator: BlockTextView.Coordinator?
    /// Clipboard used for copy/paste; tests substitute a private pasteboard.
    var pasteboard: NSPasteboard = .general
    private var actions: BlockTextActions? { coordinator?.parent?.actions }
    weak var tracker: BlockSelectionTracker?
    var blockID: UUID?
    /// Shows a block's nested text rather than its main text.
    var isNestedText = false
    private var rangeHighlight: Range<Int>?
    private var hidesInsertionPoint = false
    /// Multi-block selection covering this block (owned by the model).
    private var rangeSelectionModel: NoteEditorModel? {
        tracker?.hasRangeSelection == true ? tracker?.model : nil
    }

    convenience init() {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 480, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        self.init(frame: .zero, textContainer: container)

        drawsBackground = false
        isRichText = true
        importsGraphics = false
        // Undo is note-wide and owned by the editor model (see undo(_:)).
        allowsUndo = false
        isAutomaticLinkDetectionEnabled = false
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isContinuousSpellCheckingEnabled = true
        usesFindBar = false
        textContainerInset = .zero
        isVerticallyResizable = false
        isHorizontallyResizable = false
        focusRingType = .none
        insertionPointColor = NSColor(SNColor.textPrimary)
        setAccessibilityRole(.textArea)
    }

    // MARK: Hover

    private var hoverArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        actions?.onHoverChange(true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        actions?.onHoverChange(false)
    }

    // MARK: Multi-block selection

    /// Shows this block's part of a multi-block selection. Drawn as a
    /// temporary attribute, so the text and its own selection are untouched.
    func setRangeHighlight(_ range: Range<Int>?, isActive: Bool) {
        if hidesInsertionPoint != isActive {
            hidesInsertionPoint = isActive
            needsDisplay = true
        }
        guard range != rangeHighlight else { return }
        rangeHighlight = range
        refreshRangeHighlight()
    }

    /// Re-applies the highlight after the text was replaced.
    func refreshRangeHighlight() {
        guard let layoutManager, let length = textStorage?.length else { return }
        layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: NSRange(location: 0, length: length))
        if let range = rangeHighlight, !range.isEmpty, range.lowerBound < length {
            let clamped = NSRange(location: range.lowerBound, length: min(range.upperBound, length) - range.lowerBound)
            layoutManager.addTemporaryAttribute(.backgroundColor, value: NSColor.selectedTextBackgroundColor, forCharacterRange: clamped)
        }
        needsDisplay = true
    }

    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        super.drawInsertionPoint(in: rect, color: color, turnedOn: flag && !hidesInsertionPoint)
    }

    /// A plain drag is tracked here instead of by NSTextView so it can continue
    /// into other blocks. Double/triple clicks, modified clicks, links and
    /// dragging an existing selection keep the standard behaviour.
    override func mouseDown(with event: NSEvent) {
        // ⌃-click: the row menu, like a right click.
        if RowMenuCatcherView.isMenuClick(event), let show = actions?.showRowMenu {
            return show(event, self)
        }
        guard let tracker, let blockID, let window, event.clickCount == 1, !hasMarkedText() else {
            tracker?.clear()
            return super.mouseDown(with: event)
        }
        let modifiers = event.modifierFlags.intersection([.shift, .command, .option, .control])
        let point = convert(event.locationInWindow, from: nil)
        let index = characterIndexForInsertion(at: point)

        // Shift-click in another block extends from the caret into this one.
        if modifiers == .shift, let model = tracker.model,
           let anchor = model.rangeSelection?.anchor
               ?? model.selection.flatMap({ $0.isDetail ? nil : BlockPosition(blockID: $0.blockID, offset: $0.range.lowerBound) }),
           anchor.blockID != blockID {
            tracker.select(from: anchor, to: BlockPosition(blockID: blockID, offset: index))
            return
        }
        let selection = selectedRange()
        let insideSelection = selection.length > 0 && NSLocationInRange(index, selection) && !tracker.hasRangeSelection
        guard modifiers.isEmpty, !insideSelection, !isLink(at: point) else {
            tracker.clear()
            return super.mouseDown(with: event)
        }

        tracker.clear()
        window.makeFirstResponder(self)
        setSelectedRange(NSRange(location: index, length: 0))
        let anchor = BlockPosition(blockID: blockID, offset: index)
        let column = tracker.model?.note.blocks.first { $0.id == blockID }?.column
        var lastDrag = event
        NSEvent.startPeriodicEvents(afterDelay: 0.1, withPeriod: 0.05)
        defer { NSEvent.stopPeriodicEvents() }
        let nextEvent = trackingEvents ?? { $0.nextEvent(matching: [.leftMouseDragged, .leftMouseUp, .periodic]) }
        while let next = nextEvent(window) {
            if next.type == .leftMouseUp { break }
            if next.type == .leftMouseDragged { lastDrag = next }
            // Keeps scrolling while the pointer rests past the editor's edge.
            autoscroll(with: lastDrag)
            let location = next.type == .leftMouseDragged ? next.locationInWindow : window.mouseLocationOutsideOfEventStream
            guard let focus = tracker.position(atWindowPoint: location, inColumn: column) else { continue }
            if focus.blockID == blockID {
                tracker.clear()
                let lower = min(index, focus.offset)
                setSelectedRange(NSRange(location: lower, length: max(index, focus.offset) - lower))
            } else {
                if selectedRange().length > 0 { setSelectedRange(NSRange(location: index, length: 0)) }
                tracker.select(from: anchor, to: focus)
            }
        }
    }

    /// Event source for the drag loop; tests feed synthesized events.
    var trackingEvents: ((NSWindow) -> NSEvent?)?

    private func isLink(at point: NSPoint) -> Bool {
        guard let layoutManager, let textContainer, let storage = textStorage, storage.length > 0 else { return false }
        let glyph = layoutManager.glyphIndex(for: point, in: textContainer)
        guard layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: textContainer).contains(point) else { return false }
        let character = layoutManager.characterIndexForGlyph(at: glyph)
        return character < storage.length && storage.attribute(.link, at: character, effectiveRange: nil) != nil
    }

    /// Keys while several blocks are selected act on the whole selection.
    /// Returns true when the key was handled.
    private func handleRangeSelectionKey(_ event: NSEvent) -> Bool {
        guard let model = rangeSelectionModel, let tracker else { return false }
        let modifiers = event.modifierFlags.intersection([.command, .control])
        defer { tracker.render() }
        switch event.keyCode {
        case 51, 117: // Delete, Forward Delete
            model.deleteRangeSelection()
        case 36, 76: // Return, Enter
            model.replaceRangeSelection(with: "\n")
        case 53: // Esc
            tracker.clear()
        case 123, 126, 124, 125: // ← ↑ → ↓ collapse to the selection's start or end
            let segments = model.rangeSegments
            let toStart = event.keyCode == 123 || event.keyCode == 126
            tracker.clear()
            if let segment = toStart ? segments.first : segments.last {
                model.focus(segment.blockID, offset: toStart ? segment.range.lowerBound : segment.range.upperBound)
            }
        case 48: // Tab: nothing to indent across a text selection
            break
        default:
            let characters = event.characters ?? ""
            let isText = !characters.isEmpty && characters.unicodeScalars.allSatisfy {
                !CharacterSet.controlCharacters.contains($0) && !(0xF700...0xF8FF).contains($0.value)
            }
            guard modifiers.isEmpty, isText else {
                tracker.clear()
                return false
            }
            model.replaceRangeSelection(with: characters)
        }
        return true
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        // Moving the caret into another text field ends a multi-block selection;
        // clicking a toolbar button (which keeps no focus) does not.
        if resigned, tracker?.hasRangeSelection == true {
            DispatchQueue.main.async { [weak self] in
                guard let self, let responder = self.window?.firstResponder, responder !== self, responder is NSText else { return }
                self.tracker?.clear()
            }
        }
        return resigned
    }

    var selectedUTF16Range: Range<Int> {
        let range = selectedRange()
        return range.location..<(range.location + range.length)
    }

    /// Shift+Return inserts a soft line break inside the block instead of
    /// splitting it. Handled here, where the real key event is known.
    override func keyDown(with event: NSEvent) {
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if handleRangeSelectionKey(event) { return }
        if isReturn, modifiers == .shift {
            insertText("\n", replacementRange: selectedRange())
            return
        }
        super.keyDown(with: event)
    }

    // MARK: Undo (note-level, owned by the model)

    @objc func undo(_ sender: Any?) { actions?.onUndo() }
    @objc func redo(_ sender: Any?) { actions?.onRedo() }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        switch item.action {
        case #selector(undo(_:)): return actions?.canUndo() ?? false
        case #selector(redo(_:)): return actions?.canRedo() ?? false
        // A multi-block selection leaves this view's own selection empty, which
        // NSTextView alone would treat as "nothing to copy".
        case #selector(copy(_:)) where rangeSelectionModel != nil,
             #selector(cut(_:)) where rangeSelectionModel != nil,
             #selector(delete(_:)) where rangeSelectionModel != nil:
            return true
        default: return super.validateUserInterfaceItem(item)
        }
    }

    // MARK: Inline formatting (sent through the responder chain by menus/toolbar)

    @objc func snToggleBold(_ sender: Any?) { toggle(.bold) }
    @objc func snToggleItalic(_ sender: Any?) { toggle(.italic) }
    @objc func snToggleUnderline(_ sender: Any?) { toggle(.underline) }
    @objc func snToggleStrikethrough(_ sender: Any?) { toggle(.strikethrough) }
    @objc func snToggleCode(_ sender: Any?) { toggle(.code) }
    @objc func snEditLink(_ sender: Any?) { actions?.onEditLink(selectedUTF16Range) }

    /// With a selection the model reformats it (undoable). With only a caret,
    /// the mark applies to what is typed next.
    private func toggle(_ mark: InlineMark) {
        let range = selectedUTF16Range
        if rangeSelectionModel != nil {
            actions?.onToggleMark(mark, range) // the model formats the whole selection
            return
        }
        if !range.isEmpty {
            actions?.onToggleMark(mark, range)
            return
        }
        guard let style = coordinator?.lastStyle else { return }
        let current = typingRun
        var marks = current.marks
        if marks.contains(mark) { marks.remove(mark) } else { marks.insert(mark) }
        typingAttributes = RichTextAttributes.attributes(
            marks: marks, link: nil, family: current.fontFamily, size: current.fontSize, style: style
        )
    }

    /// Formatting that typing at the caret would use.
    private var typingRun: TextRun {
        RichTextAttributes.richText(from: NSAttributedString(string: "x", attributes: typingAttributes)).runs.first ?? TextRun("")
    }

    // MARK: Row menu

    override func rightMouseDown(with event: NSEvent) {
        guard let show = actions?.showRowMenu else { return super.rightMouseDown(with: event) }
        show(event, self)
    }

    // MARK: Dropping pictures

    /// Text drags work as usual; a drag carrying pictures is offered to the
    /// note instead, which puts them in as blocks next to this one.
    private var isImageDrag = false

    override var acceptableDragTypes: [NSPasteboard.PasteboardType] {
        super.acceptableDragTypes + ImageDrop.pasteboardTypes.filter { !super.acceptableDragTypes.contains($0) }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        isImageDrag = ImageDrop.hasImages(sender.draggingPasteboard)
        return isImageDrag ? imageDragUpdated(sender) : super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        isImageDrag ? imageDragUpdated(sender) : super.draggingUpdated(sender)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        if isImageDrag {
            actions?.onImageDragHover(nil)
        } else {
            super.draggingExited(sender)
        }
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isImageDrag || super.prepareForDragOperation(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if !isImageDrag, dropNamedLink(sender) { return true }
        guard isImageDrag else { return super.performDragOperation(sender) }
        let payload = ImageDrop.payload(from: sender.draggingPasteboard)
        actions?.onImageDragHover(nil)
        guard !payload.isEmpty, let drop = actions?.onImageDrop else { return false }
        let after = placesImagesAfter(sender)
        // Promised files (a screenshot thumbnail, a browser) arrive after the drop.
        Task { drop(await ImageDrop.load(payload), after) }
        return true
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        if isImageDrag { isImageDrag = false } else { super.concludeDragOperation(sender) }
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        isImageDrag = false
        super.draggingEnded(sender)
    }

    /// A web address dragged in from another app (a browser's link or address
    /// bar) goes in as a named link, as when pasted. Text dragged within Plico
    /// moves as usual.
    private func dropNamedLink(_ sender: NSDraggingInfo) -> Bool {
        guard !(sender.draggingSource is NSTextView), let actions,
              let link = PasteConverter.namedLink(from: sender.draggingPasteboard, template: typingRun) else { return false }
        let index = min(characterIndexForInsertion(at: convert(sender.draggingLocation, from: nil)), (string as NSString).length)
        rangeSelectionModel?.clearRangeSelection()
        tracker?.render()
        window?.makeFirstResponder(self)
        actions.onPaste([link], index..<index)
        return true
    }

    private func imageDragUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        actions?.onImageDragHover(placesImagesAfter(sender))
        return .copy
    }

    /// The lower half of the text (or anywhere in nested text) means after the block.
    private func placesImagesAfter(_ sender: NSDraggingInfo) -> Bool {
        isNestedText || convert(sender.draggingLocation, from: nil).y > bounds.midY
    }

    // MARK: Copy & paste

    /// Adds a lossless RichText copy for pasting back into Smart Notes; other
    /// apps still get the standard RTF/plain text.
    override func copy(_ sender: Any?) {
        if let model = rangeSelectionModel {
            writeBlocks(model.copiedRangeParagraphs)
            return
        }
        let range = selectedRange()
        guard range.length > 0, let storage = textStorage else { return }
        // Written eagerly: NSTextView's writeSelection(to:types:) only promises
        // the data, and the promise came back empty, leaving the clipboard blank.
        let selected = storage.attributedSubstring(from: range)
        pasteboard.clearContents()
        pasteboard.declareTypes([.string, .rtf, .smartNotesRichText], owner: nil)
        pasteboard.setString(selected.string, forType: .string)
        if let rtf = selected.rtf(from: NSRange(location: 0, length: selected.length), documentAttributes: [:]) {
            pasteboard.setData(rtf, forType: .rtf)
        }
        if let data = try? RichTextAttributes.richText(from: selected).encodedData() {
            pasteboard.setData(data, forType: .smartNotesRichText)
        }
    }

    override func cut(_ sender: Any?) {
        copy(sender)
        delete(sender)
    }

    override func delete(_ sender: Any?) {
        if let model = rangeSelectionModel {
            model.deleteRangeSelection()
            tracker?.render()
            return
        }
        super.delete(sender)
    }

    /// First ⌘A selects this block's text; ⌘A again selects the whole note.
    override func selectAll(_ sender: Any?) {
        let range = selectedRange()
        if let tracker, let model = tracker.model, tracker.hasRangeSelection || range.length == string.utf16.count, model.note.blocks.count > 1 {
            model.selectAllBlocks()
            tracker.render()
            return
        }
        super.selectAll(sender)
    }

    /// Several blocks: a lossless copy for Plico plus readable plain text.
    private func writeBlocks(_ paragraphs: [PastedParagraph]) {
        BlockClipboard.write(paragraphs, to: pasteboard)
    }

    /// Rich paste: RTF/HTML map to supported marks and blocks; multiple
    /// paragraphs become multiple blocks. Text is never dropped.
    override func paste(_ sender: Any?) {
        performPaste(plainOnly: false)
    }

    /// Edit > Paste and Match Style.
    override func pasteAsPlainText(_ sender: Any?) {
        performPaste(plainOnly: true)
    }

    private func performPaste(plainOnly: Bool) {
        guard let paragraphs = PasteConverter.paragraphs(from: pasteboard, plainOnly: plainOnly, template: typingRun) else { return }
        if let model = rangeSelectionModel {
            model.pasteOverRangeSelection(paragraphs)
            tracker?.render()
            return
        }
        actions?.onPaste(paragraphs, selectedUTF16Range)
    }

    // MARK: Layout & focus

    /// Height needed at `width`. Measured on a scratch copy: SwiftUI asks for
    /// several candidate widths, and resizing the live container for each one
    /// could leave it laid out for the wrong width (blocks overlapping).
    func height(forWidth width: CGFloat, minimumLineHeight: CGFloat) -> CGFloat {
        guard let text = textStorage, text.length > 0, width > 0 else { return minimumLineHeight }
        // SwiftUI asks again on every layout pass (resizing a picture, a window,
        // dragging a row); measuring is real work, so answers are kept until
        // the text changes.
        if heightCacheMinimum != minimumLineHeight || heightCacheText?.isEqual(to: text) != true {
            heightCache.removeAll()
            heightCacheText = NSAttributedString(attributedString: text)
            heightCacheMinimum = minimumLineHeight
        }
        if let cached = heightCache[width] { return cached }
        let height = measuredHeight(of: text, width: width, minimumLineHeight: minimumLineHeight)
        if heightCache.count > 16 { heightCache.removeAll() }
        heightCache[width] = height
        return height
    }

    private var heightCache: [CGFloat: CGFloat] = [:]
    private var heightCacheText: NSAttributedString?
    private var heightCacheMinimum: CGFloat = 0

    private func measuredHeight(of text: NSAttributedString, width: CGFloat, minimumLineHeight: CGFloat) -> CGFloat {
        let storage = NSTextStorage(attributedString: text)
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: width, height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        layout.ensureLayout(for: container)
        return max(ceil(layout.usedRect(for: container).height), minimumLineHeight)
    }

    /// Selection waiting to be applied once the view is attached.
    private(set) var pendingFocusOffset: Int?
    private var pendingFocusLength = 0
    private var pendingFocusScrolls = true

    /// Requests keyboard focus. SwiftUI may (re)attach the view to its window
    /// after this call, so the request is kept until it can actually be applied:
    /// on the next run-loop turn, or when the view moves into a window.
    func focus(atUTF16Offset offset: Int, length: Int = 0, scrollsIntoView: Bool = true) {
        pendingFocusOffset = offset
        pendingFocusLength = length
        pendingFocusScrolls = scrollsIntoView
        DispatchQueue.main.async { [weak self] in self?.applyPendingFocus() }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Fallback for `_setWatchingSuperviewClipView:` below, should AppKit rename it.
        NotificationCenter.default.removeObserver(self, name: NSView.frameDidChangeNotification, object: nil)
        applyPendingFocus()
    }

    /// A text view with a superview observes the frame changes of *every*
    /// view, waiting for a clip view to adopt it (a scroll view's document;
    /// rows never are one). With one text view per row, each layout pass
    /// sent every view's frame change to every row: the cost grew with the
    /// square of the rows, about half the time of opening a note or resizing
    /// the window. Overriding AppKit's private switch turns that off.
    @objc(_setWatchingSuperviewClipView:)
    private func setWatchingSuperviewClipView(_ watching: Bool) {}

    private func applyPendingFocus() {
        guard let offset = pendingFocusOffset, let window else { return }
        pendingFocusOffset = nil
        window.makeFirstResponder(self)
        let total = string.utf16.count
        let location = min(max(offset, 0), total)
        setSelectedRange(NSRange(location: location, length: min(pendingFocusLength, total - location)))
        if pendingFocusScrolls { scrollRangeToVisible(selectedRange()) }
    }

    // MARK: Nested rows

    var onRowFrames: (([NestedRowFrame]) -> Void)?
    private var reportedRowFrames: [NestedRowFrame]?

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        // A new width rewraps the text, moving the rows.
        reportRowFrames()
    }

    /// Tells the nested text editor where its rows start. Reported on the next
    /// run-loop turn, since this runs during layout and SwiftUI updates.
    func reportRowFrames() {
        guard onRowFrames != nil else { return }
        let frames = rowFrames()
        guard frames != reportedRowFrames else { return }
        reportedRowFrames = frames
        DispatchQueue.main.async { [weak self] in self?.onRowFrames?(frames) }
    }

    /// Where each row of the nested text starts (see `BlockEditing.nestedRows`).
    func rowFrames() -> [NestedRowFrame] {
        BlockEditing.nestedRows(in: RichText(plain: string)).map { row in
            NestedRowFrame(range: row, frame: lineRect(at: row.lowerBound).offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y))
        }
    }

    var isCaretOnFirstLine: Bool {
        let location = selectedRange().location
        return lineRect(at: location).minY <= lineRect(at: 0).minY
    }

    var isCaretOnLastLine: Bool {
        let location = selectedRange().location
        return lineRect(at: location).maxY >= lineRect(at: string.utf16.count).maxY
    }

    private func lineRect(at characterIndex: Int) -> NSRect {
        guard let layout = layoutManager, let container = textContainer else { return .zero }
        layout.ensureLayout(for: container)
        let glyphCount = layout.numberOfGlyphs
        guard glyphCount > 0 else { return .zero }
        if characterIndex >= string.utf16.count {
            if !layout.extraLineFragmentRect.isEmpty { return layout.extraLineFragmentRect }
            return layout.lineFragmentRect(forGlyphAt: glyphCount - 1, effectiveRange: nil)
        }
        return layout.lineFragmentRect(forGlyphAt: layout.glyphIndexForCharacter(at: characterIndex), effectiveRange: nil)
    }
}

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

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> BlockNSTextView {
        let view = BlockNSTextView()
        view.delegate = context.coordinator
        view.coordinator = context.coordinator
        context.coordinator.parent = self
        apply(to: view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ view: BlockNSTextView, context: Context) {
        context.coordinator.parent = self
        if content != context.coordinator.lastContent || style != context.coordinator.lastStyle {
            apply(to: view, coordinator: context.coordinator)
        }
        view.setAccessibilityLabel(accessibilityLabel)
        if let request = focusRequest, request.blockID == blockID, request.token != context.coordinator.handledFocusToken {
            context.coordinator.handledFocusToken = request.token
            view.focus(atUTF16Offset: request.offset, length: request.length, scrollsIntoView: request.scrollsIntoView)
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: BlockNSTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 480
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
        view.invalidateIntrinsicContentSize()
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
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isApplying, let view = notification.object as? BlockNSTextView, view.window?.firstResponder === view else { return }
            parent?.actions.onSelectionChange(view.selectedUTF16Range)
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard let parent, let view = textView as? BlockNSTextView else { return false }
            let selection = view.selectedRange()
            switch selector {
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

        /// Adds block commands to the standard text context menu.
        func textView(_ view: NSTextView, menu: NSMenu, for event: NSEvent, at charIndex: Int) -> NSMenu? {
            menu.addItem(.separator())
            let up = NSMenuItem(title: "Move Block Up", action: #selector(moveBlockUp), keyEquivalent: "")
            up.target = self
            let down = NSMenuItem(title: "Move Block Down", action: #selector(moveBlockDown), keyEquivalent: "")
            down.target = self
            menu.addItem(up)
            menu.addItem(down)
            return menu
        }

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

    var selectedUTF16Range: Range<Int> {
        let range = selectedRange()
        return range.location..<(range.location + range.length)
    }

    /// Shift+Return inserts a soft line break inside the block instead of
    /// splitting it. Handled here, where the real key event is known.
    override func keyDown(with event: NSEvent) {
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
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

    // MARK: Copy & paste

    /// Adds a lossless RichText copy for pasting back into Smart Notes; other
    /// apps still get the standard RTF/plain text.
    override func copy(_ sender: Any?) {
        let range = selectedRange()
        guard range.length > 0, let storage = textStorage else { return }
        pasteboard.clearContents()
        _ = writeSelection(to: pasteboard, types: [.rtf, .string])
        if let data = try? RichTextAttributes.richText(from: storage.attributedSubstring(from: range)).encodedData() {
            pasteboard.addTypes([.smartNotesRichText], owner: nil)
            pasteboard.setData(data, forType: .smartNotesRichText)
        }
    }

    override func cut(_ sender: Any?) {
        copy(sender)
        delete(sender)
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
        actions?.onPaste(paragraphs, selectedUTF16Range)
    }

    // MARK: Layout & focus

    /// Height needed at `width`. Measured on a scratch copy: SwiftUI asks for
    /// several candidate widths, and resizing the live container for each one
    /// could leave it laid out for the wrong width (blocks overlapping).
    func height(forWidth width: CGFloat, minimumLineHeight: CGFloat) -> CGFloat {
        guard let text = textStorage, text.length > 0, width > 0 else { return minimumLineHeight }
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
        applyPendingFocus()
    }

    private func applyPendingFocus() {
        guard let offset = pendingFocusOffset, let window else { return }
        pendingFocusOffset = nil
        window.makeFirstResponder(self)
        let total = string.utf16.count
        let location = min(max(offset, 0), total)
        setSelectedRange(NSRange(location: location, length: min(pendingFocusLength, total - location)))
        if pendingFocusScrolls { scrollRangeToVisible(selectedRange()) }
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

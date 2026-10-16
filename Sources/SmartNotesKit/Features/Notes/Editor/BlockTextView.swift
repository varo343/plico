import AppKit
import SwiftUI

/// Callbacks from one block's text view to the editor model.
struct BlockTextActions {
    var onChange: (RichText) -> Void
    /// Enter (without Shift) at the given caret offset.
    var onEnter: (Int) -> Void
    /// Backspace with the caret at offset 0. Return true if handled.
    var onBackspaceAtStart: () -> Bool
    /// Arrow keys at the block's edges. Return true if focus moved.
    var onExitUp: () -> Bool
    var onExitDown: () -> Bool
}

/// One logical block's text, edited by a TextKit 1 NSTextView. Each block is
/// its own text view so blocks can later be dragged and reordered as units.
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
            view.focus(atUTF16Offset: request.offset, scrollsIntoView: request.scrollsIntoView)
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: BlockNSTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 480
        return CGSize(width: width, height: nsView.height(forWidth: width, minimumLineHeight: style.lineHeight))
    }

    /// Programmatic content replacement. Undo actions recorded against the old
    /// text would point at stale ranges, so they are discarded.
    private func apply(to view: BlockNSTextView, coordinator: Coordinator) {
        let selection = view.selectedRange()
        coordinator.isApplying = true
        view.textStorage?.setAttributedString(RichTextAttributes.attributedString(for: content, style: style))
        view.typingAttributes = RichTextAttributes.typingAttributes(style: style)
        if content.isEmpty == false, selection.location <= content.utf16Length {
            view.setSelectedRange(NSRange(location: selection.location, length: 0))
        }
        coordinator.isApplying = false
        view.undoManager?.removeAllActions(withTarget: view.textStorage as Any)
        view.undoManager?.removeAllActions(withTarget: view)
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
    }
}

/// NSTextView configured for a single block (TextKit 1 for predictable layout).
final class BlockNSTextView: NSTextView {
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
        allowsUndo = true
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

    /// M1 pastes as plain text in the current style so foreign formatting can't
    /// leak in. Rich paste mapping to supported marks arrives with M2.
    override func paste(_ sender: Any?) {
        pasteAsPlainText(sender)
    }

    func height(forWidth width: CGFloat, minimumLineHeight: CGFloat) -> CGFloat {
        guard let layout = layoutManager, let container = textContainer else { return minimumLineHeight }
        if container.size.width != width {
            container.size = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        }
        layout.ensureLayout(for: container)
        return max(ceil(layout.usedRect(for: container).height), minimumLineHeight)
    }

    /// Caret position waiting to be applied once the view is attached.
    private(set) var pendingFocusOffset: Int?
    private var pendingFocusScrolls = true

    /// Requests keyboard focus. SwiftUI may (re)attach the view to its window
    /// after this call, so the request is kept until it can actually be applied:
    /// on the next run-loop turn, or when the view moves into a window.
    func focus(atUTF16Offset offset: Int, scrollsIntoView: Bool = true) {
        pendingFocusOffset = offset
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
        let location = min(max(offset, 0), string.utf16.count)
        setSelectedRange(NSRange(location: location, length: 0))
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

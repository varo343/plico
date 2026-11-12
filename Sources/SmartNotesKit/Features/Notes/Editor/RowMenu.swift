import AppKit
import SwiftUI

/// Right click on a row (its text, grip or picture): the row's tools, in a
/// Plico menu (`SNMenuList` in a floating panel) at the pointer. The row shows
/// as selected while the menu is open (`NoteEditorModel.menuRowID`).
@MainActor
enum RowMenu {
    /// - Parameter textView: the row's text view when the click was on its
    ///   text, for Cut / Copy / Paste of a text selection.
    static func entries(for id: UUID, model: NoteEditorModel, textView: NSTextView? = nil,
                        openImage: @escaping (NoteImage) -> Void) -> [SNMenuEntry] {
        guard let block = model.note.blocks.first(where: { $0.id == id }) else { return [] }
        var entries: [SNMenuEntry] = []
        func add(_ title: String, _ icon: String, shortcut: String? = nil, destructive: Bool = false, _ action: @escaping () -> Void) {
            entries.append(.item(SNMenuItem(title: title, icon: icon, isDestructive: destructive, shortcut: shortcut, action: action)))
        }

        if let textView, textView.selectedRange().length > 0 {
            add("Cut", "scissors", shortcut: "⌘X") { textView.cut(nil) }
            add("Copy", "doc.on.clipboard", shortcut: "⌘C") { textView.copy(nil) }
            add("Paste", "clipboard", shortcut: "⌘V") { textView.paste(nil) }
            entries.append(.divider())
        }
        add("Duplicate", "plus.square.on.square", shortcut: "⇧⌘D") { model.duplicateBlock(id) }
        add("Copy Row", "doc.on.doc") { BlockClipboard.write(model.paragraphs(ofBlocks: [id])) }
        if block.column == 0 {
            add("Move to Right Column", "rectangle.righthalf.inset.filled", shortcut: "⌃⌘→") { model.moveBlocks([id], toColumn: 1) }
        } else {
            add("Move to Left Column", "rectangle.lefthalf.inset.filled", shortcut: "⌃⌘←") { model.moveBlocks([id], toColumn: 0) }
        }
        entries.append(.divider())
        add("Move Up", "arrow.up", shortcut: "⌃⌘↑") { model.moveBlock(id, by: -1) }
        add("Move Down", "arrow.down", shortcut: "⌃⌘↓") { model.moveBlock(id, by: 1) }
        if block.type != .image {
            let title = block.detail.isEmpty ? "Add Nested Text" : (model.isDetailExpanded(id) ? "Hide Nested Text" : "Show Nested Text")
            add(title, "text.alignleft", shortcut: "⌥⌘N") {
                if block.detail.isEmpty || !model.isDetailExpanded(id) {
                    model.focus(id, offset: .max, isDetail: true)
                } else {
                    model.collapseDetail(id)
                }
            }
        }
        if let image = block.image {
            entries.append(.divider())
            add("Open Image", "arrow.up.left.and.arrow.down.right") { openImage(image) }
            add("Copy Image", "photo") {
                guard let picture = NoteImageCache.picture(for: image) else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([picture])
            }
            if block.imageWidth != nil {
                add("Actual Size", "1.magnifyingglass") { model.setImageWidth(nil, of: id) }
            }
            if block.type != .image {
                add("Move Image Out of the Row", "rectangle.portrait.and.arrow.right") {
                    model.detachImage(from: id, relativeTo: id, placeAfter: true)
                }
                add("Delete Image", "trash") { model.deleteImage(of: id) }
            }
        }
        entries.append(.divider())
        add("Delete Row", "trash", destructive: true) { model.deleteBlock(id) }
        return entries
    }

    private static let controller = FloatingPanelController()

    /// Opens the menu just below the pointer. `setOpen` marks the row selected
    /// until the menu closes (a pick, Esc, or a click elsewhere).
    static func show(_ entries: [SNMenuEntry], for event: NSEvent, setOpen: @escaping (Bool) -> Void) {
        guard !entries.isEmpty, let window = event.window else { return }
        // Closing a menu that is still open clears its row first.
        controller.close()
        let point = window.convertPoint(toScreen: event.locationInWindow)
        controller.onClose = nil
        controller.show(
            SNMenuList(entries: entries, minWidth: 240, iconStyle: .tile) { controller.close() },
            below: NSRect(x: point.x, y: point.y, width: 1, height: 1), in: window, acceptsKey: true
        )
        controller.onClose = { setOpen(false) }
        setOpen(true)
    }

    static var isOpen: Bool { controller.isShown }

    static func close() { controller.close() }
}

/// Over a row's grip or picture: takes right clicks (and ⌃-clicks) only, and
/// opens the row menu. Every other click and drag passes through untouched.
struct RowMenuCatcher: NSViewRepresentable {
    let open: (NSEvent) -> Void

    func makeNSView(context: Context) -> RowMenuCatcherView {
        let view = RowMenuCatcherView()
        view.open = open
        return view
    }

    func updateNSView(_ view: RowMenuCatcherView, context: Context) {
        view.open = open
    }
}

final class RowMenuCatcherView: NSView {
    var open: (NSEvent) -> Void = { _ in }

    static func isMenuClick(_ event: NSEvent?) -> Bool {
        guard let event else { return false }
        return event.type == .rightMouseDown || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        Self.isMenuClick(NSApp.currentEvent) ? super.hitTest(point) : nil
    }

    override func rightMouseDown(with event: NSEvent) { open(event) }

    override func mouseDown(with event: NSEvent) {
        if Self.isMenuClick(event) { open(event) } else { super.mouseDown(with: event) }
    }
}

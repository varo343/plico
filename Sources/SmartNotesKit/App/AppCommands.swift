import AppKit
import SwiftUI

/// Menu bar commands. `app` is nil while the store failed to open.
public struct AppCommands: Commands {
    private let app: AppModel?

    public init(app: AppModel?) {
        self.app = app
    }

    public var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Note") { app?.createNote() }
                .keyboardShortcut("n")
                .disabled(app == nil)
        }
        CommandGroup(replacing: .saveItem) {
            Button("Save") { app?.notes.flush() }
                .keyboardShortcut("s")
                .disabled(app == nil)
            Button("Export All Notes…") { app?.exportAllNotes() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(app == nil)
        }
        CommandMenu("Note") {
            Group {
                Button("Search Notes") {
                    app?.destination = .notes
                    app?.notes.requestSearchFocus()
                }
                .keyboardShortcut("f")
                Divider()
                Button("Pin / Unpin") { withSelection { app?.notes.togglePin($0) } }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                Button("Duplicate") { withSelection { app?.notes.duplicate($0) } }
                    .keyboardShortcut("d")
                Button("Move to Trash") { moveToTrashUnlessEditingText() }
                    .keyboardShortcut(.delete)
            }
            .disabled(app == nil)
        }
        CommandMenu("Format") {
            // Inline marks go to the focused block's text view (no-op elsewhere).
            Button("Bold") { EditorActions.toggle(.bold) }.keyboardShortcut("b")
            Button("Italic") { EditorActions.toggle(.italic) }.keyboardShortcut("i")
            Button("Underline") { EditorActions.toggle(.underline) }.keyboardShortcut("u")
            Button("Strikethrough") { EditorActions.toggle(.strikethrough) }.keyboardShortcut("x", modifiers: [.command, .shift])
            Button("Inline Code") { EditorActions.toggle(.code) }
            Button("Link…") { EditorActions.editLink() }.keyboardShortcut("k")
            Divider()
            Button("Body") { blockType(.paragraph) }.keyboardShortcut("0", modifiers: [.command, .option])
            Button("Heading 1") { blockType(.heading1) }.keyboardShortcut("1", modifiers: [.command, .option])
            Button("Heading 2") { blockType(.heading2) }.keyboardShortcut("2", modifiers: [.command, .option])
            Button("Heading 3") { blockType(.heading3) }.keyboardShortcut("3", modifiers: [.command, .option])
            Button("Bulleted List") { blockType(.bulletItem) }.keyboardShortcut("7", modifiers: [.command, .shift])
            Button("Numbered List") { blockType(.numberedItem) }.keyboardShortcut("8", modifiers: [.command, .shift])
            Button("Checklist") { blockType(.checklistItem) }.keyboardShortcut("l", modifiers: [.command, .shift])
            Button("Quote") { blockType(.quote) }
            Divider()
            Button("Indent") { indent(1) }.keyboardShortcut("]")
            Button("Outdent") { indent(-1) }.keyboardShortcut("[")
            // ⌃⌘↑/↓ as in Apple Notes; plain arrow shortcuts stay with text navigation.
            Button("Move Block Up") { app?.notes.editor?.moveBlock(by: -1) }.keyboardShortcut(.upArrow, modifiers: [.command, .control])
            Button("Move Block Down") { app?.notes.editor?.moveBlock(by: 1) }.keyboardShortcut(.downArrow, modifiers: [.command, .control])
        }
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { app?.destination = .settings }
                .keyboardShortcut(",")
                .disabled(app == nil)
        }
        CommandGroup(after: .sidebar) {
            Button(app?.isListVisible == false ? "Show Note List" : "Hide Note List") { app?.isListVisible.toggle() }
                .keyboardShortcut("s", modifiers: [.command, .control])
            Divider()
            ForEach(Array(SidebarDestination.primary.enumerated()), id: \.element) { index, destination in
                Button(destination.title) { app?.destination = destination }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")))
            }
            Divider()
        }
    }

    private func blockType(_ type: BlockType) {
        app?.notes.editor?.setBlockType(type)
    }

    private func indent(_ delta: Int) {
        guard let editor = app?.notes.editor, let id = editor.activeBlockID else { return }
        editor.indentBlock(id, by: delta)
    }

    private func withSelection(_ body: (UUID) -> Void) {
        guard let app, app.destination == .notes, let id = app.notes.selectedNoteID else { return }
        body(id)
    }

    /// ⌘⌫ is also "delete to line start" in text. Menu shortcuts fire before
    /// the text view sees the key, so hand it back when the user is typing.
    private func moveToTrashUnlessEditingText() {
        if let textView = NSApp.keyWindow?.firstResponder as? NSTextView {
            textView.doCommand(by: #selector(NSResponder.deleteToBeginningOfLine(_:)))
            return
        }
        withSelection { app?.notes.moveToTrash($0) }
    }
}

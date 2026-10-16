import SwiftUI

/// The four primary destinations (switched from the list column header).
/// No Archive; Settings is not a destination.
public enum SidebarDestination: String, CaseIterable, Identifiable, Hashable {
    case notes, today, mentions, trash

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .notes: "Notes"
        case .today: "Today"
        case .mentions: "Mentions"
        case .trash: "Trash"
        }
    }

    public var symbol: String {
        switch self {
        case .notes: "note.text"
        case .today: "sun.max"
        case .mentions: "envelope"
        case .trash: "trash"
        }
    }

    /// Destinations where creating a note is appropriate (shows the FAB).
    var allowsCreation: Bool { self == .notes || self == .today }
    /// Destinations whose detail column edits the selected note.
    var showsEditor: Bool { self == .notes || self == .today }
}

/// Three-column layout: sidebar · list · editor.
public struct RootView: View {
    @Bindable private var app: AppModel

    public init(app: AppModel) {
        self.app = app
    }

    public var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                SectionSwitcher(selection: $app.destination)
                    .padding(.horizontal, SNSpacing.m)
                    .padding(.top, SNSpacing.xxs)
                    .padding(.bottom, SNSpacing.s)
                    .zIndex(1) // hover labels draw above the column content
                content
            }
            .background(SNColor.card)
            .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 380)
        } detail: {
            detail
                .frame(minWidth: 420)
        }
        .overlay(alignment: .bottomTrailing) {
            if app.destination.allowsCreation {
                OrganicNewNoteButton { app.createNote() }
                    .padding(SNSpacing.l)
            }
        }
        .overlay(alignment: .bottom) {
            if let trashed = app.notes.recentlyTrashed {
                UndoTrashBanner(title: trashed.displayTitle, undo: app.notes.undoTrash, dismiss: app.notes.dismissUndo)
                    .padding(.bottom, SNSpacing.l)
                    .id(trashed.id)
            }
        }
        .frame(minWidth: 760, minHeight: 520)
        .navigationTitle("")
        // Let each column's warm surface run up under the title bar.
        .toolbarBackground(.hidden, for: .windowToolbar)
        .tint(SNColor.focusRing)
        .alert("Something went wrong", isPresented: Binding(
            get: { app.notes.errorMessage != nil },
            set: { if !$0 { app.notes.errorMessage = nil } }
        )) {
            Button("OK") { app.notes.errorMessage = nil }
        } message: {
            Text(app.notes.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch app.destination {
        case .notes:
            NotesListView(model: app.notes)
        case .trash:
            TrashView(model: app.notes)
        case .today:
            TodayView(today: app.today, notes: app.notes) { app.destination = .notes }
        case .mentions:
            EmptyState(symbol: "envelope", tint: SNColor.accentCoral, title: "Outlook isn't set up",
                       message: "Mentions will show Outlook messages you choose to follow, such as flagged mail. This version doesn't connect to Outlook yet.")
                .background(SNColor.card)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if app.destination.showsEditor, let editor = app.notes.editor {
            NoteEditorView(model: editor, notes: app.notes, defaults: app.settings.editorDefaults)
                .id(editor.note.id)
        } else {
            Group {
                switch app.destination {
                case .trash:
                    EmptyState(symbol: "arrow.uturn.backward", tint: SNColor.borderSubtle, title: "Restore a note to edit it", message: "")
                case .mentions:
                    Color.clear
                default:
                    if app.notes.hasAnyNotes {
                        EmptyState(symbol: "note.text", tint: SNColor.borderSubtle, title: "No note selected", message: "Select a note or press ⌘N.")
                    } else {
                        Color.clear // first launch: the list's "Write your first note" is the one call to action
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(SNColor.canvas)
        }
    }
}

private struct UndoTrashBanner: View {
    let title: String
    let undo: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: SNSpacing.s) {
            Text("Moved “\(title)” to Trash").lineLimit(1)
            Button("Undo", action: undo)
                .keyboardShortcut("z", modifiers: [.command, .option])
                .buttonStyle(SNCapsuleButtonStyle())
            Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }
                .buttonStyle(SNIconButtonStyle(shape: .capsule, size: CGSize(width: 22, height: 22)))
                .accessibilityLabel("Dismiss")
        }
        .font(.system(size: 13))
        .foregroundStyle(SNColor.textPrimary)
        .padding(.horizontal, SNSpacing.m)
        .padding(.vertical, SNSpacing.xs)
        .background(SNColor.card, in: Capsule())
        .overlay(Capsule().stroke(SNColor.borderSubtle))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
        .task {
            try? await Task.sleep(for: .seconds(8))
            dismiss()
        }
    }
}

/// Shown instead of the app when the store cannot open. Never pretends data is available.
public struct StartupFailureView: View {
    private let message: String
    private let retry: () -> Void

    public init(message: String, retry: @escaping () -> Void) {
        self.message = message
        self.retry = retry
    }

    public var body: some View {
        EmptyState(symbol: "exclamationmark.triangle", title: "Smart Notes couldn't open your notes", message: message) {
            Button("Try Again", action: retry)
                .keyboardShortcut(.defaultAction)
        }
        .frame(minWidth: 480, minHeight: 320)
        .background(SNColor.canvas)
    }
}

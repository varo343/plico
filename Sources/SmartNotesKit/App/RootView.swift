import SwiftUI

/// The four primary destinations. No Archive; Settings is not a destination.
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
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    /// True when the sidebar was hidden automatically for a narrow window,
    /// so it is restored when the window widens (a manual choice is respected).
    @State private var sidebarAutoCollapsed = false
    private static let collapseWidth: CGFloat = 880

    public init(app: AppModel) {
        self.app = app
    }

    public var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 190, ideal: 215, max: 240)
        } content: {
            content
                .navigationSplitViewColumnWidth(min: 250, ideal: 300, max: 360)
        } detail: {
            detail
                .frame(minWidth: 380)
        }
        // Narrow windows drop to list + editor instead of squeezing the editor.
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
            if width < Self.collapseWidth, columnVisibility == .all {
                columnVisibility = .doubleColumn
                sidebarAutoCollapsed = true
            } else if width >= Self.collapseWidth, sidebarAutoCollapsed {
                columnVisibility = .all
                sidebarAutoCollapsed = false
            }
        }
        .onChange(of: columnVisibility) { _, visibility in
            if visibility == .all { sidebarAutoCollapsed = false }
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
        .frame(minWidth: 820, minHeight: 520)
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

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: SNSpacing.xs) {
                AppMark()
                Text("Smart Notes").font(.system(size: 15, weight: .bold)).foregroundStyle(SNColor.textPrimary)
            }
            .padding(.horizontal, SNSpacing.s)
            .padding(.bottom, SNSpacing.m)
            .accessibilityElement(children: .combine)
            ForEach(SidebarDestination.allCases) { destination in
                SidebarDestinationRow(
                    title: destination.title,
                    symbol: destination.symbol,
                    isSelected: app.destination == destination
                ) {
                    app.destination = destination
                }
            }
            Spacer()
            SettingsLink {
                Label("Settings", systemImage: "gearshape")
                    .font(.system(size: 13))
                    .foregroundStyle(SNColor.textSecondary)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, SNSpacing.s)
            .padding(.bottom, SNSpacing.s)
        }
        .padding(.horizontal, SNSpacing.xs)
        .padding(.top, SNSpacing.xs)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(SNColor.sidebar)
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
            Button("Undo", action: undo).keyboardShortcut("z", modifiers: [.command, .option])
            Button { dismiss() } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain)
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

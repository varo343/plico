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
}

/// Three-column layout: sidebar · list · editor.
public struct RootView: View {
    @Bindable private var app: AppModel

    public init(app: AppModel) {
        self.app = app
    }

    public var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 215, max: 240)
        } content: {
            content
                .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 360)
        } detail: {
            detail
                .frame(minWidth: 440)
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
            EmptyState(symbol: "envelope", title: "Outlook not connected",
                       message: "Mentions will show selected Outlook messages. Coming in Milestone 4.")
                .background(SNColor.card)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if app.destination == .notes || app.destination == .today, let editor = app.notes.editor {
            NoteEditorView(model: editor, notes: app.notes)
                .id(editor.note.id)
        } else {
            EmptyState(symbol: "note.text", title: app.destination == .trash ? "Restore a note to edit it" : "No note selected",
                       message: app.destination == .notes ? "Select a note or press ⌘N." : "")
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

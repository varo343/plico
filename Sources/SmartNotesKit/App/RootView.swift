import SwiftUI

/// Sections of the app, switched from the list column header.
/// No Archive. Settings is a section like the others (your request, Oct 17).
public enum SidebarDestination: String, CaseIterable, Identifiable, Hashable, Sendable {
    case notes, today, mentions, trash, settings

    /// The four content sections (⌘1–⌘4); Settings uses ⌘,.
    public static let primary: [SidebarDestination] = [.notes, .today, .mentions, .trash]

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .notes: "Notes"
        case .today: "Today"
        case .mentions: "Mentions"
        case .trash: "Trash"
        case .settings: "Settings"
        }
    }

    public var symbol: String {
        switch self {
        case .notes: "note.text"
        case .today: "sun.max"
        case .mentions: "envelope"
        case .trash: "trash"
        case .settings: "gearshape"
        }
    }

    /// Destinations where creating a note is appropriate (shows the FAB).
    var allowsCreation: Bool { self == .notes || self == .today }
    /// Destinations whose detail column edits the selected note.
    var showsEditor: Bool { self == .notes || self == .today }
}

/// Layout: list column (with section switcher) · note card.
public struct RootView: View {
    @Bindable private var app: AppModel

    public init(app: AppModel) {
        self.app = app
    }

    public var body: some View {
        GeometryReader { proxy in
            let listWidth = effectiveListWidth(windowWidth: proxy.size.width)
            HStack(spacing: 0) {
                if app.isListVisible {
                    listColumn
                        .frame(width: listWidth)
                        .overlay(alignment: .trailing) { ColumnResizeHandle(width: $storedListWidth, current: listWidth) }
                }
                noteCard
                    .padding(.vertical, Self.cardMargin)
                    .padding(.trailing, Self.cardMargin)
                    .padding(.leading, app.isListVisible ? 0 : Self.cardMargin)
                    .padding(.top, app.isListVisible ? 0 : Self.trafficLightsHeight)
            }
        }
        .background(SNColor.sidebar)
        .ignoresSafeArea(.container, edges: .top) // content runs under the hidden title bar
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

    // MARK: Layout

    private static let cardMargin: CGFloat = 8
    /// Space kept clear for the window's traffic-light buttons.
    private static let trafficLightsWidth: CGFloat = 78
    private static let trafficLightsHeight: CGFloat = 36
    private static let minimumCardWidth: CGFloat = 400
    @AppStorage("SmartNotes.listColumnWidth") private var storedListWidth: Double = 320

    /// The list never squeezes the note below a readable width.
    private func effectiveListWidth(windowWidth: CGFloat) -> CGFloat {
        let available = windowWidth - Self.minimumCardWidth - Self.cardMargin * 2
        return max(ColumnResizeHandle.minWidth, min(CGFloat(storedListWidth), available))
    }

    private var listColumn: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Spacer().frame(width: Self.trafficLightsWidth)
                SectionSwitcher(selection: $app.destination)
                Spacer(minLength: 0)
            }
            .frame(height: 30) // vertically centered with the traffic lights
            .padding(.top, 1)
            .padding(.trailing, SNSpacing.s)
            .padding(.bottom, SNSpacing.s)
            content
        }
    }

    /// The Linear-style card that holds the note (or the section's detail).
    private var noteCard: some View {
        detail
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(SNColor.card)
            .clipShape(RoundedRectangle(cornerRadius: SNRadius.standard))
            .overlay(RoundedRectangle(cornerRadius: SNRadius.standard).strokeBorder(SNColor.borderSubtle, lineWidth: 1))
            .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
            .overlay(alignment: .topLeading) {
                Button { app.isListVisible.toggle() } label: {
                    Image(systemName: "sidebar.left").font(.system(size: 13))
                }
                .buttonStyle(SNIconButtonStyle(isActive: !app.isListVisible))
                .foregroundStyle(SNColor.textSecondary)
                .help(app.isListVisible ? "Hide list (⌃⌘S)" : "Show list (⌃⌘S)")
                .accessibilityLabel(app.isListVisible ? "Hide list" : "Show list")
                .padding(8)
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
        case .settings:
            SettingsPaneList(selection: $app.settingsPane)
        case .mentions:
            EmptyState(symbol: "envelope", tint: SNColor.accentCoral, title: "Outlook isn't set up",
                       message: "Mentions will show Outlook messages you choose to follow, such as flagged mail. This version doesn't connect to Outlook yet.")
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
                case .settings:
                    SettingsPaneView(app: app, pane: app.settingsPane)
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

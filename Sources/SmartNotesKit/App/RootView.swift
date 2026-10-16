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
}

/// Milestone 0 shell: real navigation + DI wiring; destinations are placeholders
/// until their milestones land.
public struct RootView: View {
    private let dependencies: AppDependencies
    @State private var selection: SidebarDestination? = .notes
    @State private var activeNoteCount: Int?

    public init(dependencies: AppDependencies) {
        self.dependencies = dependencies
    }

    public var body: some View {
        NavigationSplitView {
            List(SidebarDestination.allCases, selection: $selection) { destination in
                Label(destination.title, systemImage: destination.symbol)
                    .tag(destination)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 215, max: 240)
            .safeAreaInset(edge: .bottom) {
                HStack {
                    SettingsLink {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .buttonStyle(.borderless)
                    Spacer()
                }
                .padding(SNSpacing.s)
            }
        } detail: {
            detail
                .frame(minWidth: 440)
                .background(SNColor.canvas)
        }
        .frame(minWidth: 820, minHeight: 520)
        .task { refreshCount() }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection ?? .notes {
        case .notes:
            EmptyState(
                symbol: "square.and.pencil",
                title: "Write your first note",
                message: notesMessage
            )
        case .today:
            EmptyState(symbol: "sun.max", title: "Nothing scheduled for today", message: "Today arrives in Milestone 3.")
        case .mentions:
            EmptyState(symbol: "envelope", title: "Outlook not connected", message: "Mentions arrives in Milestone 4.")
        case .trash:
            EmptyState(symbol: "trash", title: "Trash is empty", message: "Trash arrives in Milestone 1.")
        }
    }

    private var notesMessage: String {
        let store = dependencies.isInMemory ? "in-memory store" : "local store"
        guard let activeNoteCount else { return "Loading…" }
        return "\(activeNoteCount) note(s) in the \(store). The note list and editor arrive in Milestones 1–2."
    }

    private func refreshCount() {
        do {
            activeNoteCount = try dependencies.notes.summaries(in: .active).count
        } catch {
            Log.persistence.error("Failed to load note summaries: \(error.localizedDescription, privacy: .public)")
            activeNoteCount = 0
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

import AppKit
import Foundation
import Observation

/// Top-level app state: the selected destination and feature models.
@MainActor
@Observable
public final class AppModel {
    public let dependencies: AppDependencies
    public let notes: NotesModel
    public let today: TodayModel
    public let settings: SettingsModel

    public var destination: SidebarDestination = .notes {
        didSet { if destination != oldValue { notes.flush() } }
    }

    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    public init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        self.notes = NotesModel(repository: dependencies.notes, settings: dependencies.settings)
        self.today = TodayModel(repository: dependencies.notes)
        self.settings = SettingsModel(store: dependencies.settings)
        notes.load()
        // Writing first: the caret starts in the open note, not in Search.
        notes.editor?.focusFirstBlock(scrollsIntoView: false)
    }

    /// FAB and ⌘N behave identically from any destination.
    public func createNote() {
        destination = .notes
        notes.createNote()
    }

    // MARK: Data

    /// Asks for a destination folder and writes a full export there.
    public func exportAllNotes() {
        notes.flush()
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Export Here"
        panel.message = "Choose where to save the Smart Notes export."
        guard panel.runModal() == .OK, let parent = panel.url else { return }
        do {
            let result = try DataExporter.export(try dependencies.notes.allNotes(), into: parent)
            let alert = NSAlert()
            alert.messageText = "Exported \(result.noteCount) notes"
            alert.informativeText = result.folder.path
            alert.addButton(withTitle: "Show in Finder")
            alert.addButton(withTitle: "OK")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.activateFileViewerSelecting([result.folder])
            }
        } catch {
            showError("Export failed", error)
        }
    }

    public func revealStoreInFinder() {
        guard let url = try? PersistenceController.defaultStoreURL() else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Permanently deletes everything. The UI confirms before calling this.
    public func deleteAllData() {
        notes.select(nil)
        do {
            try dependencies.deleteAllData()
        } catch {
            showError("Couldn't delete all data", error)
        }
        settings.reload()
        notes.sortMode = settings.settings.sortMode
        notes.reload()
    }

    private func showError(_ title: String, _ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }

    /// Flushes pending edits whenever the app may stop running or lose focus,
    /// and keeps Today's date current.
    public func startLifecycleObservers() {
        guard observers.isEmpty else { return }
        settings.applyAppearance()
        let center = NotificationCenter.default
        for name in [NSApplication.willResignActiveNotification, NSApplication.willTerminateNotification, NSWindow.willCloseNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.notes.flush() }
            })
        }
        // Today follows the local calendar: midnight, timezone changes, waking up.
        for name in [Notification.Name.NSCalendarDayChanged, .NSSystemTimeZoneDidChange, NSApplication.didBecomeActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.today.refreshDay() }
            })
        }
    }
}

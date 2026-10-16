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

    public var destination: SidebarDestination = .notes {
        didSet { if destination != oldValue { notes.flush() } }
    }

    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    public init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        self.notes = NotesModel(repository: dependencies.notes, settings: dependencies.settings)
        self.today = TodayModel(repository: dependencies.notes)
        notes.load()
        // Writing first: the caret starts in the open note, not in Search.
        notes.editor?.focusFirstBlock(scrollsIntoView: false)
    }

    /// FAB and ⌘N behave identically from any destination.
    public func createNote() {
        destination = .notes
        notes.createNote()
    }

    /// Flushes pending edits whenever the app may stop running or lose focus,
    /// and keeps Today's date current.
    public func startLifecycleObservers() {
        guard observers.isEmpty else { return }
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

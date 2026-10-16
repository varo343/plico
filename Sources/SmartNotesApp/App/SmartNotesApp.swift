import AppKit
import SmartNotesKit
import SwiftUI

@main
struct SmartNotesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var launch = LaunchState()

    var body: some Scene {
        // Single window: one editing session per note, no cross-window conflicts.
        Window("Smart Notes", id: "main") {
            switch launch.result {
            case .success(let app):
                RootView(app: app)
                    .onAppear { app.startLifecycleObservers() }
            case .failure(let error):
                StartupFailureView(message: error.localizedDescription) { launch.retry() }
            }
        }
        .commands { AppCommands(app: try? launch.result.get()) }

        Settings {
            EmptyState(symbol: "gearshape", title: "Settings", message: "Settings arrive in a later milestone.")
                .frame(width: 420, height: 260)
        }
    }
}

@MainActor
@Observable
final class LaunchState {
    private(set) var result: Result<AppModel, Error>

    init() {
        result = Self.open()
    }

    func retry() {
        result = Self.open()
    }

    private static func open() -> Result<AppModel, Error> {
        Result { AppModel(dependencies: try AppDependencies.fromLaunchArguments()) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare SwiftPM executable (`swift run`);
        // a no-op inside the .app bundle.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }
}

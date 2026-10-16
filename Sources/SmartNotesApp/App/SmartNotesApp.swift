import AppKit
import SmartNotesKit
import SwiftUI

@main
struct SmartNotesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var launch = LaunchState()

    var body: some Scene {
        WindowGroup("Smart Notes") {
            switch launch.result {
            case .success(let dependencies):
                RootView(dependencies: dependencies)
            case .failure(let error):
                StartupFailureView(message: error.localizedDescription) { launch.retry() }
            }
        }
        Settings {
            EmptyState(symbol: "gearshape", title: "Settings", message: "Settings arrive in a later milestone.")
                .frame(width: 420, height: 260)
        }
    }
}

@MainActor
@Observable
final class LaunchState {
    private(set) var result: Result<AppDependencies, Error>

    init() {
        result = Self.open()
    }

    func retry() {
        result = Self.open()
    }

    private static func open() -> Result<AppDependencies, Error> {
        Result { try AppDependencies.fromLaunchArguments() }
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

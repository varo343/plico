import AppKit
import Observation

/// App preferences. Every write re-reads the stored settings and changes only
/// the requested fields, so it never overwrites a value saved elsewhere
/// (the note list saves the sort mode into the same record).
@MainActor
@Observable
public final class SettingsModel {
    public private(set) var settings: AppSettings
    @ObservationIgnored private let store: SettingsStore

    public init(store: SettingsStore) {
        self.store = store
        self.settings = store.load()
    }

    public var editorDefaults: EditorDefaults {
        EditorDefaults(fontFamily: settings.defaultFontFamily, fontSize: settings.defaultFontSize)
    }

    public func update(_ change: (inout AppSettings) -> Void) {
        var current = store.load()
        change(&current)
        store.save(current)
        settings = current
        applyAppearance()
    }

    /// Re-reads stored settings (e.g. after deleting all data).
    public func reload() {
        settings = store.load()
        applyAppearance()
    }

    public func applyAppearance() {
        guard let app = NSApp else { return }
        switch settings.appearance {
        case .system: app.appearance = nil
        case .light: app.appearance = NSAppearance(named: .aqua)
        case .dark: app.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

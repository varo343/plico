import Foundation
import Testing
@testable import SmartNotesKit

@Suite struct SettingsStoreTests {
    private func makeStore() -> (UserDefaultsSettingsStore, UserDefaults) {
        let defaults = UserDefaults(suiteName: "SmartNotesTests.\(UUID().uuidString)")!
        return (UserDefaultsSettingsStore(defaults: defaults, key: "settings"), defaults)
    }

    @Test func defaultsWhenEmpty() {
        let (store, _) = makeStore()
        #expect(store.load() == .defaults)
        #expect(store.load().outlookFilterMode == .flagged) // safe default from spec
    }

    @Test func roundTrip() {
        let (store, _) = makeStore()
        var settings = AppSettings.defaults
        settings.sortMode = .priority
        settings.appearance = .dark
        settings.defaultFontSize = .large
        settings.outlookRules = OutlookRules(senders: ["boss@example.com"], keywords: ["invoice"])
        store.save(settings)
        #expect(store.load() == settings)
    }

    @Test func unknownValuesFallBackPerField() {
        let (store, defaults) = makeStore()
        defaults.set(Data(#"{"sortMode":"title","appearance":"neon"}"#.utf8), forKey: "settings")
        let loaded = store.load()
        #expect(loaded.sortMode == .title)
        #expect(loaded.appearance == .system)
    }
}

@MainActor
@Suite struct SettingsModelTests {
    @Test func updatesNeverClobberValuesSavedElsewhere() {
        let defaults = UserDefaults(suiteName: "SmartNotesTests.\(UUID().uuidString)")!
        let store = UserDefaultsSettingsStore(defaults: defaults, key: "settings")
        let settings = SettingsModel(store: store)

        // The note list saves the sort mode directly into the store...
        var fromList = store.load()
        fromList.sortMode = .dueDate
        store.save(fromList)
        // ...then the Settings window changes something else.
        settings.update { $0.defaultFontSize = .large }

        #expect(store.load().sortMode == .dueDate)
        #expect(store.load().defaultFontSize == .large)
        #expect(settings.editorDefaults == EditorDefaults(fontFamily: .system, fontSize: .large))
    }
}

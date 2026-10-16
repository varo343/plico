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

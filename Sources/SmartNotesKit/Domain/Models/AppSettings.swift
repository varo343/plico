import Foundation

public enum AppearancePreference: String, Codable, CaseIterable, Sendable {
    case system, light, dark
}

/// Outlook import scope. Default is `.flagged` to avoid flooding Mentions.
public enum OutlookFilterMode: String, Codable, CaseIterable, Sendable {
    case flagged
    case inbox
    case rules
}

/// User-selected senders/keywords. These are heuristics and labeled as such in UI.
public struct OutlookRules: Codable, Hashable, Sendable {
    public var senders: [String]
    public var keywords: [String]

    public init(senders: [String] = [], keywords: [String] = []) {
        self.senders = senders
        self.keywords = keywords
    }
}

public struct AppSettings: Codable, Hashable, Sendable {
    public var defaultFontFamily: FontFamilyPreset
    public var defaultFontSize: FontSizePreset
    public var appearance: AppearancePreference
    public var outlookFilterMode: OutlookFilterMode
    public var outlookRules: OutlookRules
    public var sortMode: NoteSortMode

    public init(
        defaultFontFamily: FontFamilyPreset = .system,
        defaultFontSize: FontSizePreset = .body,
        appearance: AppearancePreference = .system,
        outlookFilterMode: OutlookFilterMode = .flagged,
        outlookRules: OutlookRules = OutlookRules(),
        sortMode: NoteSortMode = .manual
    ) {
        self.defaultFontFamily = defaultFontFamily
        self.defaultFontSize = defaultFontSize
        self.appearance = appearance
        self.outlookFilterMode = outlookFilterMode
        self.outlookRules = outlookRules
        self.sortMode = sortMode
    }

    public static let defaults = AppSettings()

    // Tolerant decoding: a missing or unknown field falls back to its default
    // instead of discarding all settings.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings.defaults
        defaultFontFamily = (try? c.decode(FontFamilyPreset.self, forKey: .defaultFontFamily)) ?? d.defaultFontFamily
        defaultFontSize = (try? c.decode(FontSizePreset.self, forKey: .defaultFontSize)) ?? d.defaultFontSize
        appearance = (try? c.decode(AppearancePreference.self, forKey: .appearance)) ?? d.appearance
        outlookFilterMode = (try? c.decode(OutlookFilterMode.self, forKey: .outlookFilterMode)) ?? d.outlookFilterMode
        outlookRules = (try? c.decode(OutlookRules.self, forKey: .outlookRules)) ?? d.outlookRules
        sortMode = (try? c.decode(NoteSortMode.self, forKey: .sortMode)) ?? d.sortMode
    }
}

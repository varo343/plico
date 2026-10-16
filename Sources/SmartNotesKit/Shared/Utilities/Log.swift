import os

/// Unified logging categories. Never log note contents, email data, or tokens;
/// interpolate only identifiers/counts, and keep the default `.private` privacy
/// for anything user-derived.
public enum Log {
    private static let subsystem = "local.smartnotes.app"

    public static let app = Logger(subsystem: subsystem, category: "app")
    public static let persistence = Logger(subsystem: subsystem, category: "persistence")
    public static let outlook = Logger(subsystem: subsystem, category: "outlook")
}

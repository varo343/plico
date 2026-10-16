import Foundation

/// A calendar date with no time or timezone component ("date-only semantic").
///
/// Planned and due dates are stored as `LocalDay` rather than `Date` so that a
/// note due on 2026-03-08 stays due on 2026-03-08 regardless of timezone or DST
/// changes. Persisted as an ISO-8601 `YYYY-MM-DD` string, which also sorts
/// lexicographically in chronological order.
public struct LocalDay: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    /// Fails for impossible dates such as 2026-02-30.
    public init?(year: Int, month: Int, day: Int) {
        guard (1...9999).contains(year), (1...12).contains(month), (1...31).contains(day) else { return nil }
        let components = DateComponents(year: year, month: month, day: day)
        guard components.isValidDate(in: Self.gregorianUTC) else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    /// The day `date` falls on in `calendar`'s timezone.
    public init(date: Date, calendar: Calendar = .current) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        // Components derived from a real Date are always valid.
        self.year = c.year!
        self.month = c.month!
        self.day = c.day!
    }

    public init?(isoString: String) {
        let parts = isoString.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2])
        else { return nil }
        self.init(year: y, month: m, day: d)
    }

    public static func today(calendar: Calendar = .current, now: Date = .now) -> LocalDay {
        LocalDay(date: now, calendar: calendar)
    }

    public var isoString: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public var description: String { isoString }

    /// Start of this day in `calendar`'s timezone (for display and date pickers).
    public func startDate(in calendar: Calendar = .current) -> Date {
        // Start of day always exists, even on DST transitions.
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    public func adding(days: Int) -> LocalDay {
        let shifted = Self.gregorianUTC.date(byAdding: .day, value: days, to: startDate(in: Self.gregorianUTC))!
        return LocalDay(date: shifted, calendar: Self.gregorianUTC)
    }

    public static func < (lhs: LocalDay, rhs: LocalDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    private static let gregorianUTC: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
}

extension LocalDay: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let value = LocalDay(isoString: raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid LocalDay '\(raw)'")
        }
        self = value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(isoString)
    }
}

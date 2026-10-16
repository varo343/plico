import Foundation

/// A month for the date picker grid.
public struct CalendarMonth: Hashable, Sendable {
    public let year: Int
    public let month: Int

    public init(containing day: LocalDay) {
        year = day.year
        month = day.month
    }

    public init(year: Int, month: Int) {
        let total = year * 12 + (month - 1)
        self.year = total / 12
        self.month = total % 12 + 1
    }

    public func adding(months: Int) -> CalendarMonth {
        CalendarMonth(year: year, month: month + months)
    }

    public var firstDay: LocalDay {
        LocalDay(year: year, month: month, day: 1)!
    }

    /// 6 weeks × 7 days, starting on the calendar's first weekday (Monday in
    /// Italy, Sunday in the US), padded with days of the adjacent months.
    public func gridDays(calendar: Calendar = .current) -> [LocalDay] {
        let weekday = calendar.component(.weekday, from: firstDay.startDate(in: calendar))
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        let start = firstDay.adding(days: -leading)
        return (0..<42).map { start.adding(days: $0) }
    }

    /// Very short weekday names in display order ("M", "T"… or "L", "M"…).
    public static func weekdaySymbols(calendar: Calendar = .current) -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    public func title(calendar: Calendar = .current) -> String {
        firstDay.startDate(in: calendar).formatted(.dateTime.month(.wide).year())
    }
}

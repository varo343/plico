import Foundation
import Testing
@testable import SmartNotesKit

@Suite struct CalendarMonthTests {
    private func calendar(firstWeekday: Int) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Rome")!
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    @Test func gridStartsOnMondayInItaly() {
        // October 2026 starts on a Thursday.
        let days = CalendarMonth(year: 2026, month: 10).gridDays(calendar: calendar(firstWeekday: 2))
        #expect(days.count == 42)
        #expect(days.first?.isoString == "2026-09-28") // Monday
        #expect(days[3].isoString == "2026-10-01")
        #expect(days.last?.isoString == "2026-11-08")
    }

    @Test func gridStartsOnSundayInTheUS() {
        let days = CalendarMonth(year: 2026, month: 10).gridDays(calendar: calendar(firstWeekday: 1))
        #expect(days.first?.isoString == "2026-09-27") // Sunday
        #expect(days[4].isoString == "2026-10-01")
    }

    @Test func monthArithmeticWrapsYears() {
        #expect(CalendarMonth(year: 2026, month: 12).adding(months: 1) == CalendarMonth(year: 2027, month: 1))
        #expect(CalendarMonth(year: 2026, month: 1).adding(months: -1) == CalendarMonth(year: 2025, month: 12))
        #expect(CalendarMonth(year: 2026, month: 3).adding(months: -15) == CalendarMonth(year: 2024, month: 12))
    }

    @Test func weekdaySymbolsFollowFirstWeekday() {
        var italian = calendar(firstWeekday: 2)
        italian.locale = Locale(identifier: "it_IT")
        #expect(CalendarMonth.weekdaySymbols(calendar: italian).count == 7)
        var english = calendar(firstWeekday: 1)
        english.locale = Locale(identifier: "en_US")
        #expect(CalendarMonth.weekdaySymbols(calendar: english).first == "S")
    }
}

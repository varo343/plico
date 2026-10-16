import Foundation
import Testing
@testable import SmartNotesKit

@Suite struct LocalDayTests {
    private func calendar(_ identifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier)!
        return calendar
    }

    @Test func isoRoundTrip() {
        let day = LocalDay(year: 2026, month: 3, day: 8)!
        #expect(day.isoString == "2026-03-08")
        #expect(LocalDay(isoString: "2026-03-08") == day)
    }

    @Test(arguments: ["2026-02-30", "2026-13-01", "2026-1-01", "20260301", "", "abcd-ef-gh", "2026-03-08T00:00"])
    func rejectsInvalidStrings(_ raw: String) {
        #expect(LocalDay(isoString: raw) == nil)
    }

    @Test func leapDay() {
        #expect(LocalDay(year: 2028, month: 2, day: 29) != nil)
        #expect(LocalDay(year: 2026, month: 2, day: 29) == nil)
    }

    @Test func ordering() {
        let a = LocalDay(isoString: "2026-01-31")!
        let b = LocalDay(isoString: "2026-02-01")!
        #expect(a < b)
        #expect(a.isoString < b.isoString) // persisted form sorts the same way
    }

    @Test func addingDaysCrossesMonthAndYear() {
        #expect(LocalDay(isoString: "2026-12-31")!.adding(days: 1).isoString == "2027-01-01")
        #expect(LocalDay(isoString: "2026-03-01")!.adding(days: -1).isoString == "2026-02-28")
    }

    /// Acceptance criterion: date-only values remain stable across timezone/DST changes.
    @Test(arguments: [
        ("America/New_York", "2026-03-08"), // US DST starts
        ("America/New_York", "2026-11-01"), // US DST ends
        ("Europe/Rome", "2026-03-29"),      // EU DST starts
        ("Pacific/Auckland", "2026-04-05"),
        ("Asia/Tokyo", "2026-06-15"),
    ])
    func stableAcrossTimezonesAndDST(zone: String, iso: String) {
        let day = LocalDay(isoString: iso)!
        let cal = calendar(zone)
        #expect(LocalDay(date: day.startDate(in: cal), calendar: cal) == day)
        // Re-encoding never shifts the day, whatever zone the user is in.
        let decoded = try? JSONDecoder().decode(LocalDay.self, from: JSONEncoder().encode(day))
        #expect(decoded == day)
    }

    @Test func sameInstantIsDifferentDayInDifferentZones() {
        // 2026-06-15 23:30 in New York is already June 16 in Tokyo.
        let instant = calendar("America/New_York").date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 23, minute: 30))!
        #expect(LocalDay(date: instant, calendar: calendar("America/New_York")).isoString == "2026-06-15")
        #expect(LocalDay(date: instant, calendar: calendar("Asia/Tokyo")).isoString == "2026-06-16")
    }
}

import Foundation
import Testing
@testable import SmartNotesKit

@Suite struct TodayRulesTests {
    private let today = LocalDay(isoString: "2026-10-16")!
    private let base = Date(timeIntervalSince1970: 1_790_000_000)

    private func note(_ title: String, planned: String? = nil, due: String? = nil, priority: Priority = .none, trashed: Bool = false) -> NoteSummary {
        NoteSummary(
            id: UUID(), title: title, displayTitle: title, preview: "", createdAt: base, updatedAt: base,
            isPinned: false, deletedAt: trashed ? base : nil, priority: priority,
            plannedDate: planned.flatMap(LocalDay.init(isoString:)), dueDate: due.flatMap(LocalDay.init(isoString:)),
            manualRank: "i"
        )
    }

    private func titles(_ notes: [NoteSummary]) -> [TodayRules.Section: [String]] {
        Dictionary(uniqueKeysWithValues: TodayRules.sections(notes, today: today).map { ($0.0, $0.1.map(\.title)) })
    }

    @Test func groupsByExplicitDatesOnly() {
        let result = titles([
            note("overdue", due: "2026-10-15"),
            note("due", due: "2026-10-16"),
            note("planned", planned: "2026-10-16"),
            note("future due", due: "2026-10-17"),
            note("planned yesterday", planned: "2026-10-15"),
            note("no dates", priority: .high), // high priority alone never puts a note in Today
        ])
        #expect(result == [.overdue: ["overdue"], .dueToday: ["due"], .plannedToday: ["planned"]])
    }

    @Test func noteAppearsOnceUnderItsDeadline() {
        let result = titles([
            note("late and planned", planned: "2026-10-16", due: "2026-10-10"),
            note("due and planned", planned: "2026-10-16", due: "2026-10-16"),
        ])
        #expect(result == [.overdue: ["late and planned"], .dueToday: ["due and planned"]])
    }

    @Test func trashedNotesExcluded() {
        #expect(TodayRules.sections([note("gone", due: "2026-10-16", trashed: true)], today: today).isEmpty)
    }

    @Test func emptySectionsOmittedAndOrderFixed() {
        let sections = TodayRules.sections([note("p", planned: "2026-10-16"), note("o", due: "2026-01-01")], today: today)
        #expect(sections.map(\.0) == [.overdue, .plannedToday])
    }

    @Test func sortingWithinSections() {
        let result = titles([
            note("b", due: "2026-10-14", priority: .low),
            note("a", due: "2026-10-14", priority: .high),
            note("oldest", due: "2026-09-01"),
            note("Zed", due: "2026-10-16", priority: .high),
            note("alpha", due: "2026-10-16"),
            note("Beta", due: "2026-10-16"),
        ])
        #expect(result[.overdue] == ["oldest", "a", "b"])
        #expect(result[.dueToday] == ["Zed", "alpha", "Beta"])
    }

    /// "Today" is the user's local calendar day; a deadline never moves with timezones.
    @Test func todayFollowsLocalCalendar() {
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = TimeZone(identifier: "America/New_York")!
        // 2026-10-16 20:00 in New York = 2026-10-17 09:00 in Tokyo.
        let instant = newYork.date(from: DateComponents(year: 2026, month: 10, day: 16, hour: 20))!
        let notes = [note("due 16th", due: "2026-10-16")]
        #expect(TodayRules.sections(notes, today: LocalDay.today(calendar: newYork, now: instant)).first?.0 == .dueToday)
        #expect(TodayRules.sections(notes, today: LocalDay.today(calendar: tokyo, now: instant)).first?.0 == .overdue)
    }
}

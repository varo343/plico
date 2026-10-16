import Foundation
import Testing
@testable import SmartNotesKit

@MainActor
@Suite struct TodayAndMetadataTests {
    private let start = Date(timeIntervalSince1970: 1_790_000_000)

    private func makeModels(seed: Bool = true) throws -> (NotesModel, TodayModel, AppDependencies, TestClock) {
        let deps = try AppDependencies.inMemory(seedSampleData: seed, now: start)
        let clock = TestClock(start)
        let notes = NotesModel(repository: deps.notes, settings: deps.settings, autosaveDelay: .seconds(60), now: { clock.now })
        notes.load()
        let today = TodayModel(repository: deps.notes, now: { clock.now })
        return (notes, today, deps, clock)
    }

    private func titles(_ sections: [TodaySection]) -> [TodayRules.Section: [String]] {
        Dictionary(uniqueKeysWithValues: sections.map { ($0.kind, $0.items.map(\.summary.displayTitle)) })
    }

    @Test func sampleDataLandsInExpectedSections() throws {
        let (notes, today, _, _) = try makeModels()
        // Fixtures: report due yesterday, ideas due today, errands planned today, reading list next week.
        #expect(titles(today.sections(from: notes.activeNotes)) == [
            .overdue: ["Quarterly report"],
            .dueToday: ["Café ideas for the team offsite"],
            .plannedToday: ["Weekend errands"],
        ])
    }

    @Test func settingDatesAndPriorityPersistsAndUpdatesToday() throws {
        let (notes, today, deps, _) = try makeModels()
        let reading = try #require(notes.activeNotes.first { $0.title == "Reading list" })
        notes.setDueDate(today.today, for: reading.id)
        notes.setPriority(.high, for: reading.id)

        let stored = try #require(try deps.notes.note(id: reading.id))
        #expect(stored.dueDate == today.today && stored.priority == .high)
        #expect(stored.updatedAt == reading.updatedAt) // metadata isn't a content edit
        let dueToday = try #require(today.sections(from: notes.activeNotes).first { $0.kind == .dueToday })
        #expect(dueToday.items.first?.summary.title == "Reading list") // high priority sorts first

        notes.setDueDate(nil, for: reading.id)
        notes.setPlannedDate(nil, for: reading.id)
        #expect(try deps.notes.note(id: reading.id)?.dueDate == nil)
        #expect(!today.sections(from: notes.activeNotes).flatMap(\.items).contains { $0.id == reading.id })
    }

    @Test func metadataChangeDoesNotDisturbPendingEdits() throws {
        let (notes, _, deps, _) = try makeModels()
        let editor = try #require(notes.editor)
        editor.setTitle("Typed, not yet saved")
        notes.setPriority(.medium, for: editor.note.id)
        notes.flush()
        let stored = try #require(try deps.notes.note(id: editor.note.id))
        #expect(stored.title == "Typed, not yet saved" && stored.priority == .medium)
    }

    @Test func newNotesGetNoPriorityOrDates() throws {
        let (notes, _, _, _) = try makeModels(seed: false)
        notes.createNote()
        let created = try #require(notes.activeNotes.first)
        #expect(created.priority == .none && created.plannedDate == nil && created.dueDate == nil)
    }

    @Test func trashedNotesLeaveToday() throws {
        let (notes, today, _, _) = try makeModels()
        let errands = try #require(notes.activeNotes.first { $0.title == "Weekend errands" })
        notes.moveToTrash(errands.id)
        #expect(today.sections(from: notes.activeNotes).first { $0.kind == .plannedToday } == nil)
    }

    @Test func checklistPreviewIsReadOnlyAndRefreshesAfterSave() throws {
        let (notes, today, _, clock) = try makeModels()
        let errands = try #require(notes.activeNotes.first { $0.title == "Weekend errands" })
        func lines() -> [ChecklistLine] {
            today.sections(from: notes.activeNotes).flatMap(\.items).first { $0.id == errands.id }?.checklist ?? []
        }
        #expect(lines().map(\.isChecked) == [true, false, false])

        notes.select(errands.id)
        let editor = try #require(notes.editor)
        clock.advance(10)
        editor.toggleChecked(editor.note.blocks[1].id)
        notes.flush()
        #expect(lines().map(\.isChecked) == [true, true, false])
    }

    @Test func dayRollsOverAtMidnight() throws {
        let (notes, today, _, clock) = try makeModels()
        let before = today.today
        clock.advance(86_400)
        today.refreshDay()
        #expect(today.today == before.adding(days: 1))
        // Yesterday's "due today" note is now overdue.
        let overdue = titles(today.sections(from: notes.activeNotes))[.overdue] ?? []
        #expect(overdue.contains("Café ideas for the team offsite"))
    }
}

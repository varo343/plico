import Foundation
import Observation

/// A read-only checklist line shown on a Today card.
public struct ChecklistLine: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var text: String
    public var isChecked: Bool
}

public struct TodayItem: Identifiable, Equatable {
    public var summary: NoteSummary
    public var checklist: [ChecklistLine]
    public var id: UUID { summary.id }
}

public struct TodaySection: Identifiable, Equatable {
    public var kind: TodayRules.Section
    public var items: [TodayItem]
    public var id: TodayRules.Section { kind }
}

/// State for the Today destination. Sections are derived from the notes'
/// explicit dates; checklist previews are read-only (items are completed in the editor).
@MainActor
@Observable
public final class TodayModel {
    public private(set) var today: LocalDay
    /// Completed checklist items are hidden on cards unless this is on.
    public var showsCompletedItems = false

    @ObservationIgnored private let repository: NoteRepository
    @ObservationIgnored private let calendar: () -> Calendar
    @ObservationIgnored private let now: () -> Date
    /// Checklist lines per note, invalidated when the note's `updatedAt` changes.
    @ObservationIgnored private var checklistCache: [UUID: (updatedAt: Date, lines: [ChecklistLine])] = [:]

    public init(repository: NoteRepository, calendar: @escaping () -> Calendar = { .current }, now: @escaping () -> Date = Date.init) {
        self.repository = repository
        self.calendar = calendar
        self.now = now
        self.today = LocalDay.today(calendar: calendar(), now: now())
    }

    /// Call when the day, timezone or clock may have changed.
    public func refreshDay() {
        let current = LocalDay.today(calendar: calendar(), now: now())
        if current != today { today = current }
    }

    public func sections(from notes: [NoteSummary]) -> [TodaySection] {
        TodayRules.sections(notes, today: today).map { kind, summaries in
            TodaySection(kind: kind, items: summaries.map { TodayItem(summary: $0, checklist: checklist(for: $0)) })
        }
    }

    private func checklist(for summary: NoteSummary) -> [ChecklistLine] {
        if let cached = checklistCache[summary.id], cached.updatedAt == summary.updatedAt {
            return cached.lines
        }
        let lines = ((try? repository.note(id: summary.id))?.blocks ?? [])
            .filter { $0.type == .checklistItem }
            .map { ChecklistLine(id: $0.id, text: $0.content.plainText, isChecked: $0.isChecked) }
        checklistCache[summary.id] = (summary.updatedAt, lines)
        return lines
    }
}

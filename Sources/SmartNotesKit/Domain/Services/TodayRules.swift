import Foundation

/// Which notes appear in Today, and where. Driven only by explicit dates the
/// user set — never by age, priority or anything inferred.
public enum TodayRules {
    public enum Section: String, CaseIterable, Sendable {
        case overdue, dueToday, plannedToday

        public var title: String {
            switch self {
            case .overdue: "Overdue"
            case .dueToday: "Due today"
            case .plannedToday: "Planned today"
            }
        }
    }

    /// Notes grouped by section, each note at most once. A note that is both
    /// overdue (or due today) and planned today appears only under its deadline.
    /// Pass active notes only; trashed notes are ignored defensively.
    public static func sections(_ notes: [NoteSummary], today: LocalDay) -> [(Section, [NoteSummary])] {
        var overdue: [NoteSummary] = []
        var dueToday: [NoteSummary] = []
        var planned: [NoteSummary] = []
        for note in notes where note.deletedAt == nil {
            if let due = note.dueDate, due < today {
                overdue.append(note)
            } else if note.dueDate == today {
                dueToday.append(note)
            } else if note.plannedDate == today {
                planned.append(note)
            }
        }
        overdue.sort { a, b in
            // Oldest deadline first, then priority.
            if let x = a.dueDate, let y = b.dueDate, x != y { return x < y }
            return byPriority(a, b)
        }
        dueToday.sort(by: byPriority)
        planned.sort(by: byPriority)
        return [(.overdue, overdue), (.dueToday, dueToday), (.plannedToday, planned)].filter { !$0.1.isEmpty }
    }

    private static func byPriority(_ a: NoteSummary, _ b: NoteSummary) -> Bool {
        if a.priority != b.priority { return a.priority > b.priority }
        let order = a.displayTitle.localizedStandardCompare(b.displayTitle)
        if order != .orderedSame { return order == .orderedAscending }
        return a.id.uuidString < b.id.uuidString
    }
}

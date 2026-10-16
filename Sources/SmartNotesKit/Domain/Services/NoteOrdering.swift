import Foundation

/// Deterministic list ordering. Pinned notes always come first; the sort mode
/// applies within each group. Ties fall back to most recently updated, then ID.
public enum NoteSorter {
    public struct Groups: Equatable {
        public var pinned: [NoteSummary]
        public var others: [NoteSummary]

        public var all: [NoteSummary] { pinned + others }
    }

    public static func grouped(_ notes: [NoteSummary], by mode: NoteSortMode) -> Groups {
        let sorted = notes.sorted { areInIncreasingOrder($0, $1, mode: mode) }
        return Groups(pinned: sorted.filter(\.isPinned), others: sorted.filter { !$0.isPinned })
    }

    static func areInIncreasingOrder(_ a: NoteSummary, _ b: NoteSummary, mode: NoteSortMode) -> Bool {
        switch mode {
        case .manual:
            if a.manualRank != b.manualRank { return a.manualRank < b.manualRank }
        case .updated:
            break
        case .created:
            if a.createdAt != b.createdAt { return a.createdAt > b.createdAt }
        case .title:
            let order = a.displayTitle.localizedStandardCompare(b.displayTitle)
            if order != .orderedSame { return order == .orderedAscending }
        case .priority:
            if a.priority != b.priority { return a.priority > b.priority }
        case .dueDate:
            switch (a.dueDate, b.dueDate) {
            case let (x?, y?) where x != y: return x < y
            case (.some, nil): return true   // notes without a due date go last
            case (nil, .some): return false
            default: break
            }
        }
        if a.updatedAt != b.updatedAt { return a.updatedAt > b.updatedAt }
        return a.id.uuidString < b.id.uuidString
    }
}

/// Rank bookkeeping for Manual sort.
public enum ManualOrdering {
    /// Rank that places a new note above every existing note.
    public static func rankForNewNote(existing: [NoteSummary]) -> String {
        guard let lowest = existing.map(\.manualRank).filter(Rank.isValid).min() else { return Rank.initial }
        return (try? Rank.between(nil, lowest)) ?? Rank.initial
    }

    /// Rank directly after `id` within its own pinned/unpinned group.
    public static func rankAfter(_ id: UUID, existing: [NoteSummary]) -> String {
        guard let note = existing.first(where: { $0.id == id }) else { return rankForNewNote(existing: existing) }
        let next = existing
            .filter { $0.isPinned == note.isPinned && $0.manualRank > note.manualRank }
            .map(\.manualRank)
            .min()
        if let rank = try? Rank.between(note.manualRank, next) { return rank }
        let highest = existing.map(\.manualRank).filter(Rank.isValid).max()
        return (try? Rank.between(highest, nil)) ?? Rank.initial
    }

    /// New ranks after moving `source` rows to `destination` within one group
    /// shown in manual order (same semantics as SwiftUI's `onMove`). Only moved
    /// rows normally change; if existing ranks are unusable (duplicates or
    /// invalid keys), the whole group is renumbered.
    public static func move(in group: [NoteSummary], from source: IndexSet, to destination: Int) -> [UUID: String] {
        var order = group.map { (id: $0.id, rank: $0.manualRank) }
        let moved = source.sorted().map { order[$0] }
        let movedIDs = Set(moved.map(\.id))
        let insertion = destination - source.filter { $0 < destination }.count
        order.removeAll { movedIDs.contains($0.id) }
        order.insert(contentsOf: moved, at: min(max(insertion, 0), order.count))

        let renumbered = { Dictionary(uniqueKeysWithValues: zip(order.map(\.id), Rank.evenlySpaced(order.count))) }
        let ranks = group.map(\.manualRank)
        guard Set(ranks).count == ranks.count, ranks.allSatisfy(Rank.isValid) else { return renumbered() }

        var updates: [UUID: String] = [:]
        do {
            for i in order.indices where movedIDs.contains(order[i].id) {
                let lower = i > 0 ? order[i - 1].rank : nil
                let upper = order[(i + 1)...].first { !movedIDs.contains($0.id) }?.rank
                let rank = try Rank.between(lower, upper)
                order[i].rank = rank
                updates[order[i].id] = rank
            }
        } catch {
            return renumbered()
        }
        return updates
    }
}

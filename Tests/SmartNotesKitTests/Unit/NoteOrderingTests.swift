import Foundation
import Testing
@testable import SmartNotesKit

@Suite struct NoteOrderingTests {
    private let base = Date(timeIntervalSince1970: 1_790_000_000)

    private func summary(
        _ title: String, rank: String = "i", pinned: Bool = false, updated: TimeInterval = 0,
        created: TimeInterval = 0, priority: Priority = .none, due: String? = nil
    ) -> NoteSummary {
        NoteSummary(
            id: UUID(), title: title, displayTitle: title, preview: "",
            createdAt: base.addingTimeInterval(created), updatedAt: base.addingTimeInterval(updated),
            isPinned: pinned, deletedAt: nil, priority: priority, plannedDate: nil,
            dueDate: due.flatMap(LocalDay.init(isoString:)), manualRank: rank
        )
    }

    // MARK: Sorting

    @Test func pinnedAlwaysFirstInEveryMode() {
        let notes = [summary("b"), summary("a", pinned: true), summary("c")]
        for mode in NoteSortMode.allCases {
            let groups = NoteSorter.grouped(notes, by: mode)
            #expect(groups.pinned.map(\.title) == ["a"])
            #expect(groups.all.first?.title == "a")
        }
    }

    @Test func manualUsesRankWithinGroups() {
        let notes = [summary("x", rank: "r"), summary("y", rank: "c"), summary("p2", rank: "z", pinned: true), summary("p1", rank: "a", pinned: true)]
        let groups = NoteSorter.grouped(notes, by: .manual)
        #expect(groups.pinned.map(\.title) == ["p1", "p2"])
        #expect(groups.others.map(\.title) == ["y", "x"])
    }

    @Test func computedModes() {
        let a = summary("Banana", updated: 10, created: 1, priority: .low, due: "2026-05-02")
        let b = summary("apple", updated: 30, created: 3, priority: .high)
        let c = summary("Cherry 10", updated: 20, created: 2, priority: .high, due: "2026-05-01")
        let d = summary("Cherry 9", updated: 5, created: 4, due: "2026-05-01")
        let notes = [a, b, c, d]
        func titles(_ mode: NoteSortMode) -> [String] { NoteSorter.grouped(notes, by: mode).all.map(\.title) }

        #expect(titles(.updated) == ["apple", "Cherry 10", "Banana", "Cherry 9"])
        #expect(titles(.created) == ["Cherry 9", "apple", "Cherry 10", "Banana"])
        #expect(titles(.title) == ["apple", "Banana", "Cherry 9", "Cherry 10"]) // localized, numeric-aware
        #expect(titles(.priority) == ["apple", "Cherry 10", "Banana", "Cherry 9"]) // ties → updated
        #expect(titles(.dueDate) == ["Cherry 10", "Cherry 9", "Banana", "apple"])  // no due date last
    }

    @Test func sortingIsDeterministicForFullTies() {
        let notes = (0..<20).map { _ in summary("same") }
        let first = NoteSorter.grouped(notes, by: .title).all.map(\.id)
        let second = NoteSorter.grouped(notes.reversed(), by: .title).all.map(\.id)
        #expect(first == second)
    }

    // MARK: Manual ordering

    private func applying(_ updates: [UUID: String], to group: [NoteSummary]) -> [String] {
        group.map { note in
            var note = note
            if let rank = updates[note.id] { note.manualRank = rank }
            return note
        }
        .sorted { $0.manualRank < $1.manualRank }
        .map(\.title)
    }

    @Test(arguments: [
        ([0], 3, ["b", "c", "a", "d"]),
        ([3], 0, ["d", "a", "b", "c"]),
        ([1], 4, ["a", "c", "d", "b"]),
        ([1, 2], 0, ["b", "c", "a", "d"]),
        ([0, 3], 2, ["b", "a", "d", "c"]),
        ([2], 2, ["a", "b", "c", "d"]),
    ])
    func moveMatchesOnMoveSemantics(source: [Int], destination: Int, expected: [String]) {
        let ranks = Rank.evenlySpaced(4)
        let group = ["a", "b", "c", "d"].enumerated().map { summary($1, rank: ranks[$0]) }
        let updates = ManualOrdering.move(in: group, from: IndexSet(source), to: destination)
        #expect(applying(updates, to: group) == expected)
        #expect(updates.count <= source.count) // only moved rows rewritten
    }

    @Test func moveRenumbersWhenRanksAreDuplicated() {
        let group = ["a", "b", "c"].map { summary($0, rank: "i") }
        let updates = ManualOrdering.move(in: group, from: [2], to: 0)
        #expect(updates.count == 3)
        #expect(applying(updates, to: group) == ["c", "a", "b"])
    }

    @Test func newNoteGoesAboveEverything() {
        let notes = [summary("a", rank: "c"), summary("p", rank: "b", pinned: true)]
        let rank = ManualOrdering.rankForNewNote(existing: notes)
        #expect(rank < "b")
        #expect(ManualOrdering.rankForNewNote(existing: []) == Rank.initial)
    }

    @Test func rankAfterStaysInsideGroup() {
        let a = summary("a", rank: "c")
        let pinned = summary("p", rank: "d", pinned: true)
        let b = summary("b", rank: "k")
        let rank = ManualOrdering.rankAfter(a.id, existing: [a, pinned, b])
        #expect(rank > "c" && rank < "k")
    }
}

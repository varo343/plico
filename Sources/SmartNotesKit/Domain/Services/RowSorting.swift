import Foundation

/// How Sort Rows orders a note's lists.
public enum RowSortOrder: String, CaseIterable, Sendable {
    /// High, Medium, Low, then custom tags, then untagged; completed rows last.
    case severity
    /// Open rows first, completed rows last; otherwise the order is kept.
    case completion

    /// Menu titles for the two directions.
    public func title(reversed: Bool) -> String {
        switch (self, reversed) {
        case (.severity, false): "High → Low"
        case (.severity, true): "Low → High"
        case (.completion, false): "Open First"
        case (.completion, true): "Completed First"
        }
    }
}

/// Sorting rows within a note. Only lists move: runs of consecutive list items
/// or tagged rows. Headings, plain paragraphs and the like stay where they are
/// and separate one list from the next, and so does the edge of a column. A row's indented rows move with it
/// and are sorted among themselves. Sorting is stable.
extension BlockEditing {
    /// Sorts every list in the note, or only `blockIDs` (a multi-block
    /// selection) as one list. `reversed` turns the order upside down: Low
    /// first (untagged before it) or completed first. A severity sort keeps
    /// completed rows last either way. Returns nil when the order doesn't change.
    public static func sortRows(_ note: Note, by order: RowSortOrder, reversed: Bool = false, within blockIDs: Set<UUID>? = nil) -> Note? {
        let blocks = note.blocks
        let runs: [Range<Int>]
        if let blockIDs {
            // The selected rows of each column, sorted as one list per column.
            runs = Dictionary(grouping: blocks.indices.filter { blockIDs.contains(blocks[$0].id) }) { blocks[$0].column }
                .values.compactMap { indices in
                    guard let first = indices.min(), let last = indices.max(), last > first else { return nil }
                    return first..<last + 1
                }
            guard !runs.isEmpty else { return nil }
        } else {
            runs = listRuns(blocks)
        }
        var ordered = blocks
        for run in runs {
            ordered.replaceSubrange(run, with: sorted(Array(blocks[run])) { sortKey($0, order, reversed: reversed) })
        }
        return reordered(note, ordered)
    }

    /// After a row is checked: it moves below the other rows of its list (at
    /// the same level), into the completed part. Unchecked again, it moves
    /// back up, just above the first completed row. Nil when it stays put.
    public static func settlingChecked(_ note: Note, blockID: UUID) -> Note? {
        let blocks = note.blocks
        guard let index = blocks.firstIndex(where: { $0.id == blockID }),
              let run = listRuns(blocks).first(where: { $0.contains(index) }) else { return nil }
        let level = blocks[index].indentLevel
        // Its siblings: the rows around it up to its parent (a less indented row).
        var lower = index
        while lower > run.lowerBound, blocks[lower - 1].indentLevel >= level { lower -= 1 }
        var upper = index + 1
        while upper < run.upperBound, blocks[upper].indentLevel >= level { upper += 1 }

        var units = Self.units(Array(blocks[lower..<upper]))
        guard let position = units.firstIndex(where: { $0.first?.id == blockID }) else { return nil }
        let unit = units.remove(at: position)
        let destination = blocks[index].isChecked
            ? units.count
            : min(position, units.firstIndex { $0.first?.isChecked == true } ?? units.count)
        units.insert(unit, at: destination)
        var ordered = blocks
        ordered.replaceSubrange(lower..<upper, with: units.flatMap { $0 })
        return reordered(note, ordered)
    }

    /// Ranges of consecutive sortable rows (list items or tagged rows), two or more long.
    static func listRuns(_ blocks: [NoteBlock]) -> [Range<Int>] {
        var runs: [Range<Int>] = []
        var start: Int?
        for index in blocks.indices {
            let block = blocks[index]
            let isSortable = block.type.isListLike || block.tag != nil
            // A list ends where its column does.
            if let first = start, blocks[first].column != block.column {
                runs.append(first..<index)
                start = nil
            }
            if isSortable, start == nil { start = index }
            if !isSortable, let first = start {
                runs.append(first..<index)
                start = nil
            }
        }
        if let first = start { runs.append(first..<blocks.count) }
        return runs.filter { $0.count > 1 }
    }

    /// Rows grouped with the more indented rows under them.
    private static func units(_ blocks: [NoteBlock]) -> [[NoteBlock]] {
        guard let base = blocks.map(\.indentLevel).min() else { return [] }
        var units: [[NoteBlock]] = []
        for block in blocks {
            if block.indentLevel <= base || units.isEmpty {
                units.append([block])
            } else {
                units[units.count - 1].append(block)
            }
        }
        return units
    }

    private static func sorted(_ blocks: [NoteBlock], by key: (NoteBlock) -> [Int]) -> [NoteBlock] {
        let units = units(blocks).map { unit in [unit[0]] + sorted(Array(unit.dropFirst()), by: key) }
        return units.enumerated()
            .sorted { lhs, rhs in
                let (a, b) = (key(lhs.element[0]), key(rhs.element[0]))
                return a != b ? a.lexicographicallyPrecedes(b) : lhs.offset < rhs.offset
            }
            .flatMap(\.element)
    }

    private static func sortKey(_ block: NoteBlock, _ order: RowSortOrder, reversed: Bool) -> [Int] {
        let done = block.type == .checklistItem && block.isChecked ? 1 : 0
        let direction = reversed ? -1 : 1
        switch order {
        case .completion:
            return [done * direction]
        case .severity:
            let severity = switch block.tag {
            case .priority(let priority): 3 - priority.weight // High 0, Medium 1, Low 2
            case .custom: 3
            case nil: 4
            }
            return [done, severity * direction]
        }
    }

    /// The note with its blocks in `ordered`: they take the existing ranks in
    /// turn, or fresh evenly spaced ones if ranks repeat.
    private static func reordered(_ note: Note, _ ordered: [NoteBlock]) -> Note? {
        guard ordered.map(\.id) != note.blocks.map(\.id) else { return nil }
        let ranks = note.blocks.map(\.rank)
        let newRanks = Set(ranks).count == ranks.count ? ranks : Rank.evenlySpaced(ranks.count)
        var note = note
        note.blocks = zip(ordered, newRanks).map { block, rank in
            var block = block
            block.rank = rank
            return block
        }
        return note
    }
}

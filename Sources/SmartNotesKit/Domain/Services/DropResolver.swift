import CoreGraphics
import Foundation

/// Where a dragged row lands, from the pointer's vertical position and the
/// rows' frames (top to bottom). Shared by block and note reordering.
public enum DropResolver {
    public struct Target: Equatable, Sendable {
        public var id: UUID
        public var placeAfter: Bool
    }

    /// The row under the pointer decides: its upper half means "before it",
    /// its lower half "after it". Above the first row → before the first;
    /// below the last → after the last. Returns nil when the drop would not
    /// change the order (dropping a row next to itself).
    public static func target(pointerY y: CGFloat, frames: [(id: UUID, frame: CGRect)], dragged: UUID) -> Target? {
        let others = frames.filter { $0.id != dragged }
        guard let first = others.first, let last = others.last else { return nil }
        let target: Target
        if y < first.frame.minY {
            target = Target(id: first.id, placeAfter: false)
        } else if y > last.frame.maxY {
            target = Target(id: last.id, placeAfter: true)
        } else if let row = others.first(where: { y >= $0.frame.minY && y <= $0.frame.maxY }) {
            target = Target(id: row.id, placeAfter: y > row.frame.midY)
        } else {
            // In a gap between rows: attach to the nearest row edge.
            let nearest = others.min { abs($0.frame.midY - y) < abs($1.frame.midY - y) }!
            target = Target(id: nearest.id, placeAfter: y > nearest.frame.midY)
        }
        return changesOrder(target, frames: frames.map(\.id), dragged: dragged) ? target : nil
    }

    private static func changesOrder(_ target: Target, frames ids: [UUID], dragged: UUID) -> Bool {
        guard let from = ids.firstIndex(of: dragged), let to = ids.firstIndex(of: target.id) else { return false }
        // "After the row just above" or "before the row just below" is where it already is.
        if target.placeAfter, to == from - 1 { return false }
        if !target.placeAfter, to == from + 1 { return false }
        return true
    }
}

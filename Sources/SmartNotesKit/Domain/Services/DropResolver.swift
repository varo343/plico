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
        guard let target = insertion(pointerY: y, frames: frames.filter { $0.id != dragged }) else { return nil }
        return changesOrder(target, frames: frames.map(\.id), dragged: dragged) ? target : nil
    }

    /// Where something that is not one of the rows (a nested row dragged out)
    /// would be inserted, by the same rule as `target`.
    public static func insertion(pointerY y: CGFloat, frames: [(id: UUID, frame: CGRect)]) -> Target? {
        guard let first = frames.first, let last = frames.last else { return nil }
        if y < first.frame.minY { return Target(id: first.id, placeAfter: false) }
        if y > last.frame.maxY { return Target(id: last.id, placeAfter: true) }
        if let row = frames.first(where: { y >= $0.frame.minY && y <= $0.frame.maxY }) {
            return Target(id: row.id, placeAfter: y > row.frame.midY)
        }
        // In a gap between rows: attach to the nearest row edge.
        let nearest = frames.min { abs($0.frame.midY - y) < abs($1.frame.midY - y) }!
        return Target(id: nearest.id, placeAfter: y > nearest.frame.midY)
    }

    /// The row a dragged block would be tucked into (as nested text): the pointer
    /// is over the middle of another row. Its top and bottom edges, up to
    /// `edge` points each, still mean "before" / "after" for reordering.
    public static func nestTarget(pointerY y: CGFloat, frames: [(id: UUID, frame: CGRect)], dragged: UUID, edge: CGFloat = 10) -> UUID? {
        frames.first { row in
            let inset = min(row.frame.height * 0.25, edge)
            return row.id != dragged && y > row.frame.minY + inset && y < row.frame.maxY - inset
        }?.id
    }

    /// Where the dragged row ends up in `order` if dropped on `target`.
    public static func finalIndex(order: [UUID], dragged: UUID, target: Target?) -> Int? {
        guard let from = order.firstIndex(of: dragged) else { return nil }
        guard let target, let to = order.firstIndex(of: target.id) else { return from }
        let insertion = target.placeAfter ? to + 1 : to
        return insertion > from ? insertion - 1 : insertion
    }

    /// Live preview while dragging: how far row `id` moves to make room. Rows
    /// between the dragged row's old and new place slide by `gap` (the dragged
    /// row's height plus spacing); everything else stays. The dragged row itself
    /// follows the pointer, so it gets 0 here.
    public static func previewOffset(of id: UUID, order: [UUID], dragged: UUID, target: Target?, gap: CGFloat) -> CGFloat {
        guard id != dragged, let from = order.firstIndex(of: dragged), let index = order.firstIndex(of: id),
              let final = finalIndex(order: order, dragged: dragged, target: target) else { return 0 }
        if final > from, index > from, index <= final { return -gap }
        if final < from, index >= final, index < from { return gap }
        return 0
    }

    private static func changesOrder(_ target: Target, frames ids: [UUID], dragged: UUID) -> Bool {
        guard let from = ids.firstIndex(of: dragged), let to = ids.firstIndex(of: target.id) else { return false }
        // "After the row just above" or "before the row just below" is where it already is.
        if target.placeAfter, to == from - 1 { return false }
        if !target.placeAfter, to == from + 1 { return false }
        return true
    }
}

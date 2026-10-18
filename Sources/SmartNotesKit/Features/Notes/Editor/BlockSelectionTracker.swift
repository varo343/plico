import AppKit

/// Lets a mouse drag that starts in one block's text view select text in the
/// blocks around it. Each block is its own NSTextView, so a drag would
/// otherwise stop at the block's edge. Owned by the editor; text views
/// register themselves and the model keeps the resulting selection.
@MainActor
final class BlockSelectionTracker {
    weak var model: NoteEditorModel?
    private var views: [UUID: WeakTextView] = [:]

    private struct WeakTextView {
        weak var view: BlockNSTextView?
    }

    func register(_ view: BlockNSTextView, for id: UUID) {
        views[id] = WeakTextView(view: view)
        views = views.filter { $0.value.view != nil }
    }

    var hasRangeSelection: Bool { model?.rangeSelection != nil }

    /// The block position under a window point. Above the first block maps to
    /// its start, below the last to its end; between blocks, the next block.
    func position(atWindowPoint point: NSPoint) -> BlockPosition? {
        guard let blocks = model?.note.blocks else { return nil }
        let ordered = blocks.compactMap { block in views[block.id]?.view.map { (block.id, $0) } }
        guard let last = ordered.last else { return nil }
        for (id, view) in ordered {
            let local = view.convert(point, from: nil) // text views are flipped
            guard local.y <= view.bounds.maxY else { continue }
            if local.y < view.bounds.minY {
                return BlockPosition(blockID: id, offset: 0)
            }
            let x = min(max(local.x, view.bounds.minX), view.bounds.maxX)
            return BlockPosition(blockID: id, offset: view.characterIndexForInsertion(at: NSPoint(x: x, y: local.y)))
        }
        return BlockPosition(blockID: last.0, offset: last.1.string.utf16.count)
    }

    func select(from anchor: BlockPosition, to focus: BlockPosition) {
        model?.setRangeSelection(anchor: anchor, focus: focus)
        render()
    }

    func clear() {
        guard hasRangeSelection else { return }
        model?.clearRangeSelection()
        render()
    }

    /// Paints the selection now. SwiftUI applies the same state on its next
    /// update, but none happens while the mouse-tracking loop runs.
    func render() {
        let segments = model?.rangeSegments ?? []
        let ranges = Dictionary(segments.map { ($0.blockID, $0.range) }, uniquingKeysWith: { $1 })
        for (id, box) in views {
            box.view?.setRangeHighlight(ranges[id], isActive: !segments.isEmpty)
        }
    }
}

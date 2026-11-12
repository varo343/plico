import Observation
import SwiftUI

/// The hover highlight of a list in the left column (notes, Today, Mentions,
/// Trash, Settings): one highlight glides from row to row under the pointer
/// instead of each row lighting up on its own. It hides on the spot when the
/// pointer leaves the list and, coming back, appears on the row under the
/// pointer instead of gliding from where it was.
///
/// The list gets `.glidingHover()`; each row `.glidingHoverRow(id)`. The
/// highlight is drawn under the rows, so it passes beneath a selected row's card.
@MainActor
@Observable
final class GlidingHover {
    fileprivate(set) var hovered: AnyHashable?
    fileprivate(set) var isVisible = false

    fileprivate func enter(_ id: AnyHashable) {
        if isVisible {
            hovered = id
        } else {
            var placement = Transaction()
            placement.disablesAnimations = true
            withTransaction(placement) { hovered = id }
            isVisible = true
        }
    }

    fileprivate func leave() { isVisible = false }
}

private struct GlidingHoverKey: EnvironmentKey {
    static var defaultValue: GlidingHover? { nil }
}

extension EnvironmentValues {
    fileprivate var glidingHover: GlidingHover? {
        get { self[GlidingHoverKey.self] }
        set { self[GlidingHoverKey.self] = newValue }
    }
}

private struct GlidingHoverList: ViewModifier {
    let color: Color
    let isEnabled: Bool
    @State private var hover = GlidingHover()

    func body(content: Content) -> some View {
        content
            .menuHighlight(on: hover.hovered, isVisible: hover.isVisible && isEnabled,
                           color: color, cornerRadius: SNRadius.standard)
            .onHover { inside in if !inside { hover.leave() } }
            .environment(\.glidingHover, hover)
    }
}

private struct GlidingHoverRow: ViewModifier {
    let id: AnyHashable
    @Environment(\.glidingHover) private var hover

    func body(content: Content) -> some View {
        content
            .menuHighlightRow(id)
            .onHover { inside in if inside { hover?.enter(id) } }
    }
}

extension View {
    /// A list whose rows share one gliding hover highlight (see `GlidingHover`).
    /// - Parameter isEnabled: false hides it (e.g. while a row is dragged).
    func glidingHover(color: Color = SNColor.borderSubtle.opacity(0.45), isEnabled: Bool = true) -> some View {
        modifier(GlidingHoverList(color: color, isEnabled: isEnabled))
    }

    /// A row of a `glidingHover()` list.
    func glidingHoverRow<ID: Hashable>(_ id: ID) -> some View {
        modifier(GlidingHoverRow(id: AnyHashable(id)))
    }
}

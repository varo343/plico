import AppKit
import SwiftUI

/// Invisible handle on the list column's trailing edge: drag to resize
/// (the width is remembered), with the standard resize cursor on hover.
struct ColumnResizeHandle: View {
    /// Fits the header in its widest state: the section switcher with its longest
    /// name expanded on hover (≈221), plus the Mentions controls (58), spacing and
    /// margins. Narrower, hovering a section pushed the header past the column.
    /// `ListColumnLayoutTests` keeps this in sync with the real views.
    static let minWidth: CGFloat = 320
    static let maxWidth: CGFloat = 440

    @Binding var width: Double
    let current: CGFloat
    @State private var dragStart: CGFloat?
    @State private var isHovered = false

    var body: some View {
        Color.clear
            .frame(width: 8)
            .contentShape(Rectangle())
            .onHover { inside in
                guard inside != isHovered else { return }
                isHovered = inside
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let start = dragStart ?? current
                        dragStart = start
                        width = Double(min(max(start + value.translation.width, Self.minWidth), Self.maxWidth))
                    }
                    .onEnded { _ in dragStart = nil }
            )
            .offset(x: 4)
            .accessibilityHidden(true)
    }
}

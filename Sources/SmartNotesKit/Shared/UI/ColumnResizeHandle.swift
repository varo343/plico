import AppKit
import SwiftUI

/// Invisible handle on the list column's trailing edge: drag to resize
/// (the width is remembered), with the standard resize cursor on hover.
struct ColumnResizeHandle: View {
    static let minWidth: CGFloat = 270
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

import SwiftUI

/// The signature floating New Note action: yellow organic blob, ink outline,
/// rounded plus. Same behavior as ⌘N. No looping animation.
public struct OrganicNewNoteButton: View {
    private let action: () -> Void
    @FocusState private var isFocused: Bool

    public init(action: @escaping () -> Void) {
        self.action = action
    }

    public var body: some View {
        Button(action: action) { EmptyView() }
            .buttonStyle(BlobButtonStyle(isFocused: isFocused))
            .focusable()
            .focused($isFocused)
            .focusEffectDisabled()
            .accessibilityLabel("New Note")
            .accessibilityHint("Creates a note and starts editing it")
            .help("New Note (⌘N)")
    }
}

private struct BlobButtonStyle: ButtonStyle {
    let isFocused: Bool

    func makeBody(configuration: Configuration) -> some View {
        BlobButtonBody(pressed: configuration.isPressed, isFocused: isFocused)
    }
}

private struct BlobButtonBody: View {
    let pressed: Bool
    let isFocused: Bool
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let size: CGFloat = 64

    var body: some View {
        let scale: CGFloat = reduceMotion ? 1 : (pressed ? 0.97 : (isHovered ? 1.03 : 1))
        let shadowOffset: CGFloat = pressed ? 1.5 : (isHovered ? 4 : 3)

        ZStack {
            // Hard offset "cartoon" shadow.
            OrganicBlobShape()
                .fill(SNColor.ink.opacity(0.85))
                .offset(x: shadowOffset * 0.7, y: shadowOffset)
            OrganicBlobShape()
                .fill(SNColor.accentYellow)
            OrganicBlobShape()
                .stroke(SNColor.ink, style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
            PlusGlyph()
                .stroke(SNColor.ink, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .frame(width: 22, height: 22)
            if isFocused {
                OrganicBlobShape()
                    .stroke(SNColor.focusRing, lineWidth: 3)
                    .padding(-6)
            }
        }
        .frame(width: size, height: size)
        .contentShape(OrganicBlobShape())
        .scaleEffect(scale)
        .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.6), value: pressed)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isHovered)
        .onHover { isHovered = $0 }
    }
}

private struct PlusGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

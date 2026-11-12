import SwiftUI

/// The signature floating New Note action: yellow organic blob, ink outline,
/// rounded plus. Same behavior as ⌘N. Hover squashes the blob like jelly and
/// turns the plus; a click bounces it. One-shot motions only, never looping.
public struct OrganicNewNoteButton: View {
    private let action: () -> Void
    @FocusState private var isFocused: Bool

    public init(action: @escaping () -> Void) {
        self.action = action
    }

    public var body: some View {
        // No `.focusable()`: clicking must not leave a focus ring. With Full
        // Keyboard Access the button is still reachable with Tab.
        Button(action: action) { EmptyView() }
            .buttonStyle(BlobButtonStyle(isFocused: isFocused))
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
    /// Bumped on hover-in and on click to replay the one-shot motions.
    @State private var hovers = 0
    @State private var clicks = 0
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
                .modifier(PlusTurn(trigger: hovers + clicks, isEnabled: !reduceMotion))
            if isFocused {
                OrganicBlobShape()
                    .stroke(SNColor.focusRing, lineWidth: 3)
                    .padding(-6)
            }
        }
        .frame(width: size, height: size)
        .modifier(BlobJelly(hovers: hovers, clicks: clicks, isEnabled: !reduceMotion))
        .contentShape(OrganicBlobShape())
        .scaleEffect(scale)
        .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.6), value: pressed)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isHovered)
        .onHover { inside in
            isHovered = inside
            if inside { hovers += 1 }
        }
        // Released (the action fires on release): bounce.
        .onChange(of: pressed) { _, isPressed in
            if !isPressed { clicks += 1 }
        }
    }
}

/// Squash and stretch: a soft jelly wobble on hover, a bigger bounce on click.
private struct BlobJelly: ViewModifier {
    let hovers: Int
    let clicks: Int
    let isEnabled: Bool

    private struct Stretch {
        var x: Double = 1
        var y: Double = 1
    }

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .keyframeAnimator(initialValue: Stretch(), trigger: hovers) { view, s in
                    view.scaleEffect(x: s.x, y: s.y, anchor: .bottom)
                } keyframes: { _ in
                    KeyframeTrack(\.x) { CubicKeyframe(1.07, duration: 0.1); CubicKeyframe(0.98, duration: 0.12); CubicKeyframe(1, duration: 0.14) }
                    KeyframeTrack(\.y) { CubicKeyframe(0.94, duration: 0.1); CubicKeyframe(1.03, duration: 0.12); CubicKeyframe(1, duration: 0.14) }
                }
                .keyframeAnimator(initialValue: Stretch(), trigger: clicks) { view, s in
                    view.scaleEffect(x: s.x, y: s.y)
                } keyframes: { _ in
                    KeyframeTrack(\.x) {
                        CubicKeyframe(1.12, duration: 0.07); CubicKeyframe(0.9, duration: 0.12)
                        CubicKeyframe(1.04, duration: 0.1); CubicKeyframe(1, duration: 0.12)
                    }
                    KeyframeTrack(\.y) {
                        CubicKeyframe(0.86, duration: 0.07); CubicKeyframe(1.1, duration: 0.12)
                        CubicKeyframe(0.97, duration: 0.1); CubicKeyframe(1, duration: 0.12)
                    }
                }
        } else {
            content
        }
    }
}

/// The plus turns a quarter (it looks the same afterwards, so it snaps back unseen).
private struct PlusTurn: ViewModifier {
    let trigger: Int
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content.keyframeAnimator(initialValue: 0.0, trigger: trigger) { view, angle in
                view.rotationEffect(.degrees(angle))
            } keyframes: { _ in
                KeyframeTrack {
                    // Overshoots a little, then lands exactly on 90° so the snap back is invisible.
                    CubicKeyframe(100, duration: 0.2)
                    CubicKeyframe(90, duration: 0.14)
                    CubicKeyframe(0, duration: 0.001)
                }
            }
        } else {
            content
        }
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

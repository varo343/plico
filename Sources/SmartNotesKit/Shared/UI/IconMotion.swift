import SwiftUI

/// Each icon moves in a way that matches what it represents (a trash lid
/// swings, a pin drops, a gear turns…). Replayed when `trigger` changes;
/// skipped entirely with Reduce Motion.
enum IconMotion {
    case swing        // hinged at the top: trash, bins
    case drop         // falls in and settles: pins
    case spin(Double) // rotates by n degrees: sun, gear, sort
    case lift         // rises and lands: envelope, share
    case flip         // turns over: calendars
    case wave         // waves from the bottom: flags, priorities
    case pop          // grows and settles: duplicate, sparkles, headings
    case pulse        // short throb: text styles
    case slide        // nudges sideways: lists, sidebar
    case wiggle       // quick shake: links, quotes
    case shake        // horizontal alert shake: warnings, drives

    static func forSymbol(_ symbol: String) -> IconMotion {
        let name = symbol.replacingOccurrences(of: ".fill", with: "")
        switch name {
        case "trash", "xmark.bin", "trash.slash": return .swing
        case "pin", "pin.slash": return .drop
        case "sun.max", "sunrise": return .spin(90)
        case "gearshape": return .spin(120)
        case "arrow.up.arrow.down": return .spin(180)
        case "clock.arrow.circlepath", "arrow.uturn.backward": return .spin(-180)
        case "envelope", "square.and.arrow.up": return .lift
        case "calendar", "calendar.badge.clock": return .flip
        case "flag", "flag.checkered", "exclamationmark", "exclamationmark.2", "arrow.down": return .wave
        case "plus.square.on.square", "sparkles", "textformat.size", "textformat.size.larger", "textformat.size.smaller": return .pop
        case "bold", "italic", "underline", "strikethrough", "textformat", "character", "character.book.closed", "circle.dashed": return .pulse
        case "list.bullet", "list.number", "checklist", "sidebar.left", "note.text", "text.alignleft", "hand.draw": return .slide
        case "exclamationmark.triangle", "internaldrive", "xmark.circle": return .shake
        default: return .wiggle
        }
    }
}

private struct IconMotionState {
    var angle: Double = 0
    var x: Double = 0
    var y: Double = 0
    var scale: Double = 1
    var turn: Double = 0 // rotation around the vertical axis (flip)
}

/// One keyframe: target value and duration.
private typealias Frame = (value: Double, duration: Double)

private extension IconMotion {
    var anchor: UnitPoint {
        switch self {
        case .swing: .top
        case .wave: .bottomLeading
        default: .center
        }
    }

    // Per-property keyframes. Empty means "stays at rest".
    var angle: [Frame] {
        switch self {
        case .swing: [(-16, 0.09), (11, 0.1), (-5, 0.09), (0, 0.12)]
        case .drop: [(-10, 0.1), (4, 0.12), (0, 0.16)]
        case .spin(let degrees): [(degrees, 0.42), (0, 0.001)] // symmetric icons look the same after the turn
        case .lift: [(-6, 0.12), (0, 0.2)]
        case .wave: [(-12, 0.08), (9, 0.09), (-5, 0.08), (0, 0.1)]
        case .wiggle: [(-14, 0.07), (12, 0.08), (-6, 0.07), (0, 0.1)]
        default: []
        }
    }

    var x: [Frame] {
        switch self {
        case .slide: [(3.5, 0.1), (-1, 0.12), (0, 0.12)]
        case .shake: [(-2.5, 0.05), (2.5, 0.06), (-1.5, 0.05), (0, 0.06)]
        default: []
        }
    }

    var y: [Frame] {
        switch self {
        case .drop: [(-5, 0.1), (1.5, 0.12), (0, 0.14)]
        case .lift: [(-4, 0.12), (0.8, 0.12), (0, 0.12)]
        default: []
        }
    }

    var scale: [Frame] {
        switch self {
        case .pop: [(1.25, 0.1), (0.95, 0.12), (1, 0.12)]
        case .pulse: [(1.18, 0.09), (0.94, 0.09), (1, 0.1)]
        default: []
        }
    }

    var turn: [Frame] {
        switch self {
        case .flip: [(180, 0.18), (360, 0.18), (0, 0.001)]
        default: []
        }
    }
}

private struct IconMotionModifier<Trigger: Equatable & Sendable>: ViewModifier {
    let motion: IconMotion
    let trigger: Trigger
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            let anchor = motion.anchor
            let (angle, x, y, scale, turn) = (motion.angle, motion.x, motion.y, motion.scale, motion.turn)
            content.keyframeAnimator(initialValue: IconMotionState(), trigger: trigger) { view, state in
                view
                    .rotation3DEffect(.degrees(state.turn), axis: (x: 0, y: 1, z: 0))
                    .rotationEffect(.degrees(state.angle), anchor: anchor)
                    .scaleEffect(state.scale)
                    .offset(x: state.x, y: state.y)
            } keyframes: { _ in
                KeyframeTrack(\.angle) { for frame in angle { CubicKeyframe(frame.value, duration: frame.duration) } }
                KeyframeTrack(\.x) { for frame in x { CubicKeyframe(frame.value, duration: frame.duration) } }
                KeyframeTrack(\.y) { for frame in y { CubicKeyframe(frame.value, duration: frame.duration) } }
                KeyframeTrack(\.scale) { for frame in scale { CubicKeyframe(frame.value, duration: frame.duration) } }
                KeyframeTrack(\.turn) { for frame in turn { CubicKeyframe(frame.value, duration: frame.duration) } }
            }
        }
    }
}

extension View {
    /// Plays the motion that suits `symbol` whenever `trigger` changes.
    func iconMotion<Trigger: Equatable & Sendable>(for symbol: String, on trigger: Trigger) -> some View {
        modifier(IconMotionModifier(motion: IconMotion.forSymbol(symbol), trigger: trigger))
    }
}

/// Incremented by button styles each time the pointer enters the button,
/// so icons animate on hover of the whole control, not just the glyph.
private struct HoverPulseKey: EnvironmentKey {
    static let defaultValue = 0
}

extension EnvironmentValues {
    var snHoverPulse: Int {
        get { self[HoverPulseKey.self] }
        set { self[HoverPulseKey.self] = newValue }
    }
}

/// SF Symbol that plays its meaning-specific motion when its button is hovered.
struct MotionIcon: View {
    let symbol: String
    var size: CGFloat = 13
    var weight: Font.Weight = .regular
    @Environment(\.snHoverPulse) private var pulse

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size, weight: weight))
            .iconMotion(for: symbol, on: pulse)
    }
}

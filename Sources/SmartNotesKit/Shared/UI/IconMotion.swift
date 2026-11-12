import SwiftUI

/// One keyframe: target value and how long it takes to get there.
struct IconKeyframe: Sendable {
    var value: Double
    var duration: Double

    init(_ value: Double, _ duration: Double) {
        self.value = value
        self.duration = duration
    }
}

/// Each icon moves like the thing it shows: a trash lid swings, a pin is
/// pushed in, bold text gets fatter, a calendar page hops. Every property has
/// its own keyframes; an empty track stays at rest. Replayed when the trigger
/// changes; skipped entirely with Reduce Motion. All motions are 2D (no 3D
/// turns) and end exactly at rest.
struct IconMotion: Sendable {
    var anchor: UnitPoint = .center
    var angle: [IconKeyframe] = []
    var x: [IconKeyframe] = []
    var y: [IconKeyframe] = []
    var scale: [IconKeyframe] = []
    var scaleX: [IconKeyframe] = []
    var scaleY: [IconKeyframe] = []

    private typealias K = IconKeyframe

    static func forSymbol(_ symbol: String) -> IconMotion {
        switch symbol.replacingOccurrences(of: ".fill", with: "") {
        // Things you throw away or close
        case "trash", "xmark.bin":
            IconMotion(anchor: .top, angle: [K(-14, 0.08), K(9, 0.09), K(-4, 0.08), K(0, 0.1)], y: [K(-1.5, 0.08), K(0, 0.2)])
        case "trash.slash", "pin.slash", "tag.slash", "exclamationmark.triangle", "exclamationmark.circle", "xmark.circle":
            shake
        case "xmark":
            IconMotion(angle: [K(90, 0.2), K(0, 0.001)]) // a quarter turn looks the same

        // Pins, tags, flags
        case "pin":
            IconMotion(anchor: .bottom, angle: [K(-12, 0.1), K(0, 0.16)], y: [K(-4.5, 0.1), K(1, 0.07), K(0, 0.12)],
                       scaleY: [K(1.06, 0.1), K(0.84, 0.07), K(1, 0.14)])
        case "tag":
            IconMotion(anchor: .topLeading, angle: [K(12, 0.1), K(-7, 0.1), K(3, 0.09), K(0, 0.1)])
        case "flag":
            IconMotion(anchor: .bottomLeading, angle: [K(-10, 0.09), K(7, 0.1), K(-3, 0.09), K(0, 0.1)])
        case "flag.checkered":
            IconMotion(anchor: .bottomLeading, angle: [K(-8, 0.1), K(4, 0.1), K(0, 0.1)], y: [K(-2.5, 0.1), K(0, 0.2)])

        // Priorities: more marks, more urgency
        case "exclamationmark":
            IconMotion(y: [K(-2, 0.08), K(0, 0.14)])
        case "exclamationmark.2":
            IconMotion(y: [K(-3, 0.08), K(0.5, 0.08), K(0, 0.12)], scale: [K(1.08, 0.08), K(1, 0.2)])
        case "exclamationmark.3":
            IconMotion(y: [K(-3.5, 0.07), K(1, 0.07), K(-1.5, 0.07), K(0, 0.1)], scale: [K(1.15, 0.07), K(1, 0.24)])

        // Time
        case "calendar":
            // A page hopping off the pad: calm, no turn.
            IconMotion(anchor: .bottom, y: [K(-2.5, 0.1), K(0.6, 0.1), K(0, 0.12)], scaleY: [K(1.06, 0.1), K(0.96, 0.1), K(1, 0.12)])
        case "calendar.badge.clock":
            IconMotion(angle: [K(-8, 0.05), K(8, 0.06), K(-6, 0.05), K(5, 0.05), K(0, 0.07)]) // an alarm ringing
        case "sun.max":
            IconMotion(angle: [K(45, 0.4), K(0, 0.001)], scale: [K(1.12, 0.16), K(1, 0.24)]) // 8 rays: 45° looks the same
        case "sunrise":
            IconMotion(y: [K(2.5, 0.1), K(-1.5, 0.16), K(0, 0.14)], scale: [K(0.92, 0.1), K(1.06, 0.16), K(1, 0.14)])
        case "clock.arrow.circlepath":
            IconMotion(angle: [K(-360, 0.55), K(0, 0.001)])
        case "arrow.clockwise":
            IconMotion(angle: [K(360, 0.55), K(0, 0.001)])

        // Settings, sorting, undo
        case "gearshape":
            // Mechanical: two clicks of half a tooth each.
            IconMotion(angle: [K(22.5, 0.1), K(22.5, 0.06), K(45, 0.1), K(0, 0.001)])
        case "arrow.up.arrow.down":
            IconMotion(y: [K(-2, 0.08), K(2, 0.1), K(0, 0.1)], scaleY: [K(0.9, 0.08), K(1.05, 0.1), K(1, 0.1)])
        case "arrow.uturn.backward":
            IconMotion(angle: [K(-35, 0.14), K(6, 0.1), K(0, 0.12)], x: [K(-2, 0.14), K(0, 0.2)])

        // Mail and sharing
        case "envelope":
            IconMotion(angle: [K(-6, 0.12), K(3, 0.1), K(0, 0.1)], y: [K(-3.5, 0.12), K(0.8, 0.1), K(0, 0.12)])
        case "envelope.open":
            IconMotion(y: [K(-2, 0.1), K(0, 0.16)], scale: [K(1.08, 0.1), K(1, 0.16)])
        case "square.and.arrow.up":
            IconMotion(anchor: .bottom, y: [K(-3, 0.1), K(0.5, 0.1), K(0, 0.1)], scaleY: [K(1.1, 0.1), K(1, 0.2)])
        case "tray":
            IconMotion(anchor: .bottom, y: [K(1, 0.08), K(0, 0.2)], scaleY: [K(0.85, 0.08), K(1.06, 0.1), K(1, 0.12)])
        case "at":
            IconMotion(angle: [K(25, 0.12), K(-8, 0.1), K(0, 0.1)])
        case "externaldrive", "internaldrive":
            IconMotion(y: [K(1, 0.05), K(-1, 0.05), K(0.5, 0.05), K(0, 0.05)]) // a disk humming

        // Writing and creating
        case "square.and.pencil":
            IconMotion(x: [K(1.5, 0.07), K(-1, 0.07), K(1, 0.07), K(0, 0.08)], y: [K(-1, 0.07), K(1, 0.07), K(-0.5, 0.07), K(0, 0.08)])
        case "plus.square.on.square":
            IconMotion(x: [K(2, 0.1), K(0, 0.16)], y: [K(-2, 0.1), K(0, 0.16)], scale: [K(1.05, 0.1), K(1, 0.16)])
        // Row tools
        case "doc.on.doc":
            IconMotion(x: [K(2, 0.08), K(0, 0.14)], y: [K(-2, 0.08), K(0, 0.14)])
        case "doc.on.clipboard", "clipboard":
            IconMotion(y: [K(-2.5, 0.08), K(0.5, 0.08), K(0, 0.1)])
        case "scissors":
            IconMotion(angle: [K(-14, 0.07), K(10, 0.07), K(-4, 0.07), K(0, 0.08)])
        case "rectangle.righthalf.inset.filled":
            IconMotion(x: [K(3, 0.1), K(-1, 0.08), K(0, 0.1)])
        case "rectangle.lefthalf.inset.filled":
            IconMotion(x: [K(-3, 0.1), K(1, 0.08), K(0, 0.1)])
        case "arrow.up":
            IconMotion(y: [K(-3, 0.09), K(0.8, 0.07), K(0, 0.1)])
        case "arrow.down":
            IconMotion(y: [K(3, 0.09), K(-0.8, 0.07), K(0, 0.1)])
        case "photo":
            IconMotion(angle: [K(-6, 0.09), K(0, 0.14)], scale: [K(1.12, 0.09), K(1, 0.16)])
        case "arrow.up.left.and.arrow.down.right", "1.magnifyingglass":
            IconMotion(scale: [K(1.2, 0.1), K(0.96, 0.08), K(1, 0.1)])
        case "rectangle.portrait.and.arrow.right":
            IconMotion(x: [K(3, 0.1), K(0, 0.14)])
        case "sparkles":
            IconMotion(angle: [K(18, 0.12), K(-6, 0.1), K(0, 0.12)], scale: [K(1.22, 0.12), K(0.96, 0.1), K(1, 0.12)])
        case "hand.draw":
            IconMotion(anchor: .bottom, angle: [K(-12, 0.07), K(10, 0.08), K(-5, 0.07), K(0, 0.1)])
        case "magnifyingglass":
            IconMotion(x: [K(1.5, 0.08), K(0, 0.08), K(-1.5, 0.08), K(0, 0.08)], y: [K(0, 0.08), K(-1.5, 0.08), K(0, 0.08), K(0, 0.08)])

        // Text styles act out their meaning
        case "bold":
            IconMotion(scaleX: [K(1.22, 0.1), K(0.96, 0.1), K(1, 0.1)])
        case "italic":
            IconMotion(anchor: .bottom, angle: [K(-14, 0.1), K(4, 0.1), K(0, 0.1)])
        case "underline":
            IconMotion(y: [K(1.5, 0.08), K(-0.5, 0.08), K(0, 0.1)], scaleX: [K(1.12, 0.08), K(1, 0.18)])
        case "strikethrough":
            IconMotion(scaleX: [K(0.85, 0.08), K(1.08, 0.08), K(1, 0.1)])
        case "chevron.left.forwardslash.chevron.right", "ellipsis":
            IconMotion(scaleX: [K(1.25, 0.1), K(0.95, 0.1), K(1, 0.1)])
        case "link":
            IconMotion(angle: [K(-25, 0.1), K(10, 0.1), K(0, 0.12)])
        case "textformat.size.larger":
            pop(1.25)
        case "textformat.size":
            pop(1.18)
        case "textformat.size.smaller":
            pop(1.12)
        case "textformat", "character", "character.book.closed", "circle.dashed":
            IconMotion(scale: [K(1.14, 0.09), K(0.97, 0.09), K(1, 0.1)])
        case "text.quote":
            IconMotion(angle: [K(-8, 0.1), K(0, 0.16)], scale: [K(1.15, 0.1), K(1, 0.16)])

        // Lists and layout
        case "checklist", "checkmark", "checkmark.square":
            IconMotion(angle: [K(-8, 0.08), K(0, 0.18)], scale: [K(1.1, 0.08), K(1, 0.18)]) // ticked off
        case "list.bullet", "list.number":
            IconMotion(x: [K(3, 0.1), K(-1, 0.1), K(0, 0.12)])
        case "text.alignleft", "note.text":
            IconMotion(x: [K(-2.5, 0.1), K(1, 0.1), K(0, 0.1)])
        case "sidebar.left":
            IconMotion(x: [K(-3, 0.1), K(0.8, 0.1), K(0, 0.1)])

        default:
            pop(1.1)
        }
    }

    private static let shake = IconMotion(x: [K(-2.5, 0.05), K(2.5, 0.06), K(-1.5, 0.05), K(1, 0.05), K(0, 0.06)])

    private static func pop(_ peak: Double) -> IconMotion {
        IconMotion(scale: [K(peak, 0.1), K(1 - (peak - 1) / 4, 0.1), K(1, 0.1)])
    }
}

private struct IconMotionState {
    var angle: Double = 0
    var x: Double = 0
    var y: Double = 0
    var scale: Double = 1
    var scaleX: Double = 1
    var scaleY: Double = 1
}

private struct IconMotionModifier<Trigger: Equatable & Sendable>: ViewModifier {
    let motion: IconMotion
    let trigger: Trigger
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            let motion = motion
            content.keyframeAnimator(initialValue: IconMotionState(), trigger: trigger) { view, state in
                view
                    .rotationEffect(.degrees(state.angle), anchor: motion.anchor)
                    .scaleEffect(x: state.scale * state.scaleX, y: state.scale * state.scaleY, anchor: motion.anchor)
                    .offset(x: state.x, y: state.y)
            } keyframes: { _ in
                KeyframeTrack(\.angle) { for k in motion.angle { CubicKeyframe(k.value, duration: k.duration) } }
                KeyframeTrack(\.x) { for k in motion.x { CubicKeyframe(k.value, duration: k.duration) } }
                KeyframeTrack(\.y) { for k in motion.y { CubicKeyframe(k.value, duration: k.duration) } }
                KeyframeTrack(\.scale) { for k in motion.scale { CubicKeyframe(k.value, duration: k.duration) } }
                KeyframeTrack(\.scaleX) { for k in motion.scaleX { CubicKeyframe(k.value, duration: k.duration) } }
                KeyframeTrack(\.scaleY) { for k in motion.scaleY { CubicKeyframe(k.value, duration: k.duration) } }
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

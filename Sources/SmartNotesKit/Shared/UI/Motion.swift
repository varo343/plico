import SwiftUI

/// Shared motion. Every animation goes through `snAnimation`, which turns
/// movement off when the user enables Reduce Motion.
enum SNMotion {
    /// Pressed state: quick squash with a little spring back.
    static let press = Animation.spring(response: 0.22, dampingFraction: 0.6)
    static let hover = Animation.easeOut(duration: 0.14)
    /// Selection changes, menus opening, layout changes.
    static let snappy = Animation.snappy(duration: 0.24)
}

private struct ReduceMotionAwareAnimation<Value: Equatable>: ViewModifier {
    let animation: Animation
    let value: Value
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

extension View {
    func snAnimation<Value: Equatable>(_ animation: Animation, value: Value) -> some View {
        modifier(ReduceMotionAwareAnimation(animation: animation, value: value))
    }

    /// Press feedback for custom buttons.
    func snPressEffect(_ isPressed: Bool, scale: CGFloat = 0.94) -> some View {
        modifier(PressEffect(isPressed: isPressed, scale: scale))
    }
}

private struct PressEffect: ViewModifier {
    let isPressed: Bool
    let scale: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed && !reduceMotion ? scale : 1)
            .animation(reduceMotion ? nil : SNMotion.press, value: isPressed)
    }
}

/// Entrance for floating surfaces: a small scale-up from the anchor edge plus fade.
struct PopIn: ViewModifier {
    var anchor: UnitPoint = .top
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(shown || reduceMotion ? 1 : 0.94, anchor: anchor)
            .opacity(shown ? 1 : 0)
            .onAppear {
                withAnimation(reduceMotion ? .easeOut(duration: 0.1) : SNMotion.snappy) { shown = true }
            }
    }
}

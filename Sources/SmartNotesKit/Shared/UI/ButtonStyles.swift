import SwiftUI

/// Shape used for hover/pressed highlights. Inside a capsule container use
/// `.capsule` so inner and outer curves stay concentric.
enum SNHighlightShape {
    case rounded(CGFloat)
    case capsule
}

/// Icon-sized control with hover, pressed and active states.
struct SNIconButtonStyle: ButtonStyle {
    var isActive = false
    var shape: SNHighlightShape = .rounded(8)
    var size = CGSize(width: 28, height: 26)

    func makeBody(configuration: Configuration) -> some View {
        SNIconButtonBody(configuration: configuration, isActive: isActive, shape: shape, size: size)
    }
}

private struct SNIconButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let isActive: Bool
    let shape: SNHighlightShape
    let size: CGSize
    @State private var isHovered = false
    @State private var pulse = 0
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .frame(minWidth: size.width, minHeight: size.height)
            .opacity(isEnabled ? 1 : 0.45)
            .background { highlight }
            .contentShape(Rectangle())
            .snPressEffect(configuration.isPressed, scale: 0.9)
            .snAnimation(SNMotion.hover, value: isHovered)
            .environment(\.snHoverPulse, pulse)
            .onHover { inside in
                isHovered = inside && isEnabled
                if inside { pulse += 1 }
            }
    }

    private var fill: Color {
        if configuration.isPressed { return SNColor.borderSubtle }
        if isActive { return SNColor.borderSubtle.opacity(0.9) }
        if isHovered { return SNColor.borderSubtle.opacity(0.55) }
        return .clear
    }

    @ViewBuilder
    private var highlight: some View {
        // Hand-drawn hover/active shapes (cartoon), still following the
        // container's curve (rounded vs capsule).
        switch shape {
        case .rounded(let radius): WobblyRoundedRectShape(radius: radius).fill(fill)
        case .capsule: WobblyCapsuleShape(variant: 1, amplitude: 1.6).fill(fill)
        }
    }
}

/// Text button in a capsule: quiet outline at rest, ink outline on hover.
struct SNCapsuleButtonStyle: ButtonStyle {
    var isDestructive = false

    func makeBody(configuration: Configuration) -> some View {
        SNCapsuleButtonBody(configuration: configuration, isDestructive: isDestructive)
    }
}

private struct SNCapsuleButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let isDestructive: Bool
    @State private var isHovered = false
    @State private var pulse = 0
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .labelStyle(.titleAndIcon)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(isEnabled ? SNColor.textPrimary : SNColor.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                WobblyCapsuleShape(variant: 2, amplitude: isHovered ? 1.8 : 1).fill(configuration.isPressed ? SNColor.borderSubtle
                    : (isHovered ? (isDestructive ? SNColor.accentCoral : SNColor.borderSubtle.opacity(0.6)) : SNColor.card))
            )
            .overlay(WobblyCapsuleShape(variant: 2, amplitude: isHovered ? 1.8 : 1).stroke(SNColor.borderSubtle, lineWidth: 1))
            .contentShape(Capsule())
            .opacity(isEnabled ? 1 : 0.55)
            .snPressEffect(configuration.isPressed)
            .snAnimation(SNMotion.hover, value: isHovered)
            .environment(\.snHoverPulse, pulse)
            .onHover { inside in
                isHovered = inside && isEnabled
                if inside { pulse += 1 }
            }
    }
}

/// Small label that appears next to a control on hover. Shown in its own
/// floating panel so nothing in the window can cover or clip it.
/// Decorative for VoiceOver: controls carry their own accessibility label.
struct HoverLabel: ViewModifier {
    let text: String
    var edge: Edge = .bottom
    @State private var anchor = AnchorBox()
    @State private var controller = FloatingPanelController()
    @State private var showTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .background(AnchorReader(box: anchor))
            .onHover { hovering in
                showTask?.cancel()
                if hovering {
                    showTask = Task {
                        try? await Task.sleep(for: .milliseconds(350))
                        if !Task.isCancelled { show() }
                    }
                } else {
                    controller.close()
                }
            }
            .onDisappear {
                showTask?.cancel()
                controller.close()
            }
    }

    private func show() {
        guard let window = anchor.view?.window, let rect = anchor.screenRect, window.isVisible else { return }
        controller.show(TooltipBubble(text: text), below: rect, in: window, acceptsKey: false,
                        centered: true, preferAbove: edge == .top, passesClicksThrough: true)
    }
}

private struct TooltipBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(SNColor.textPrimary)
            .fixedSize()
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(WobblyRoundedRectShape(radius: 8, variant: 2).fill(SNColor.card))
            .overlay(WobblyRoundedRectShape(radius: 8, variant: 2).stroke(SNColor.borderSubtle, lineWidth: 1))
            .shadow(color: .black.opacity(0.14), radius: 8, y: 4)
            .modifier(PopIn())
    }
}

extension View {
    func hoverLabel(_ text: String, edge: Edge = .bottom) -> some View {
        modifier(HoverLabel(text: text, edge: edge))
    }
}

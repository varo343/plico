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
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .frame(minWidth: size.width, minHeight: size.height)
            .opacity(isEnabled ? 1 : 0.45)
            .background { highlight }
            .contentShape(Rectangle())
            .onHover { isHovered = $0 && isEnabled }
    }

    private var fill: Color {
        if configuration.isPressed { return SNColor.borderSubtle }
        if isActive { return SNColor.borderSubtle.opacity(0.9) }
        if isHovered { return SNColor.borderSubtle.opacity(0.55) }
        return .clear
    }

    @ViewBuilder
    private var highlight: some View {
        switch shape {
        case .rounded(let radius): RoundedRectangle(cornerRadius: radius).fill(fill)
        case .capsule: Capsule().fill(fill)
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
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .labelStyle(.titleAndIcon)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(isEnabled ? SNColor.textPrimary : SNColor.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(configuration.isPressed ? SNColor.borderSubtle
                    : (isHovered ? (isDestructive ? SNColor.accentCoral : SNColor.borderSubtle.opacity(0.6)) : SNColor.card))
            )
            .overlay(Capsule().strokeBorder(SNColor.borderSubtle, lineWidth: 1))
            .contentShape(Capsule())
            .opacity(isEnabled ? 1 : 0.55)
            .onHover { isHovered = $0 && isEnabled }
    }
}

/// Small label that appears next to a control on hover (faster and more
/// legible than the system tooltip). Decorative for VoiceOver: controls carry
/// their own accessibility label.
struct HoverLabel: ViewModifier {
    let text: String
    var edge: Edge = .bottom
    @State private var isShown = false
    @State private var showTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                showTask?.cancel()
                if hovering {
                    showTask = Task {
                        try? await Task.sleep(for: .milliseconds(250))
                        if !Task.isCancelled { isShown = true }
                    }
                } else {
                    isShown = false
                }
            }
            .overlay(alignment: edge == .bottom ? .bottom : .top) {
                if isShown {
                    Text(text)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(SNColor.textPrimary)
                        .fixedSize()
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(SNColor.card, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(SNColor.borderSubtle, lineWidth: 1))
                        .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
                        .offset(y: edge == .bottom ? 30 : -30)
                        .transition(reduceMotion ? .identity : .opacity)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .animation(.easeOut(duration: 0.12), value: isShown)
    }
}

extension View {
    func hoverLabel(_ text: String, edge: Edge = .bottom) -> some View {
        modifier(HoverLabel(text: text, edge: edge))
    }
}

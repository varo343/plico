import SwiftUI

/// Small app mark for the sidebar: ink-outlined blob with a note glyph.
struct AppMark: View {
    var size: CGFloat = 24

    var body: some View {
        ZStack {
            OrganicBlobShape()
                .fill(SNColor.outline.opacity(0.9))
                .offset(x: 1, y: 1.5)
            OrganicBlobShape()
                .fill(SNColor.card)
            OrganicBlobShape()
                .stroke(SNColor.outline, lineWidth: 1.5)
            VStack(alignment: .leading, spacing: size * 0.09) {
                Capsule().frame(width: size * 0.42, height: 1.6)
                Capsule().frame(width: size * 0.32, height: 1.6)
                Capsule().frame(width: size * 0.38, height: 1.6)
            }
            .foregroundStyle(SNColor.outline)
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(-6))
        .accessibilityHidden(true)
    }
}

/// Empty-state illustration: a tinted blob with an ink outline and symbol.
/// Fixed shapes (never randomized) so it reads as one consistent style.
struct EmptyStateIllustration: View {
    let symbol: String
    var tint: Color = SNColor.accentMint

    var body: some View {
        ZStack {
            OrganicBlobShape()
                .fill(SNColor.outline.opacity(0.85))
                .offset(x: 2.5, y: 3.5)
            OrganicBlobShape()
                .fill(tint)
            OrganicBlobShape()
                .stroke(SNColor.outline, style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(SNColor.outline)
        }
        .frame(width: 84, height: 80)
        .rotationEffect(.degrees(-5))
        .accessibilityHidden(true)
    }
}

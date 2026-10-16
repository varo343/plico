import SwiftUI

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

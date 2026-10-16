import SwiftUI

/// Empty-state illustration: a soft tinted organic blob with a symbol.
/// Fixed shape (never randomized) so it reads as one consistent style.
struct EmptyStateIllustration: View {
    let symbol: String
    var tint: Color = SNColor.accentMint

    var body: some View {
        ZStack {
            OrganicBlobShape()
                .fill(tint)
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(SNColor.textPrimary.opacity(0.75))
        }
        .frame(width: 76, height: 72)
        .rotationEffect(.degrees(-5))
        .accessibilityHidden(true)
    }
}

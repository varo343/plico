import SwiftUI

/// Calm, centered zero-state used by every destination.
public struct EmptyState<Actions: View>: View {
    private let symbol: String
    private let tint: Color
    private let title: String
    private let message: String
    private let actions: Actions

    public init(
        symbol: String, tint: Color = SNColor.accentMint, title: String, message: String,
        @ViewBuilder actions: () -> Actions = { EmptyView() }
    ) {
        self.symbol = symbol
        self.tint = tint
        self.title = title
        self.message = message
        self.actions = actions()
    }

    public var body: some View {
        VStack(spacing: SNSpacing.s) {
            EmptyStateIllustration(symbol: symbol, tint: tint)
                .padding(.bottom, SNSpacing.xs)
            Text(title)
                .font(SNFont.section)
                .foregroundStyle(SNColor.textPrimary)
                .multilineTextAlignment(.center)
            if !message.isEmpty {
                Text(message)
                    .font(SNFont.secondary)
                    .foregroundStyle(SNColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }
            actions
                .padding(.top, SNSpacing.xs)
        }
        .padding(SNSpacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }
}

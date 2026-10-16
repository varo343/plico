import SwiftUI

/// Calm, centered zero-state used by every destination.
public struct EmptyState<Actions: View>: View {
    private let symbol: String
    private let title: String
    private let message: String
    private let actions: Actions

    public init(symbol: String, title: String, message: String, @ViewBuilder actions: () -> Actions = { EmptyView() }) {
        self.symbol = symbol
        self.title = title
        self.message = message
        self.actions = actions()
    }

    public var body: some View {
        VStack(spacing: SNSpacing.s) {
            Image(systemName: symbol)
                .font(.system(size: 36, weight: .regular))
                .foregroundStyle(SNColor.textSecondary)
                .accessibilityHidden(true)
            Text(title)
                .font(SNFont.section)
                .foregroundStyle(SNColor.textPrimary)
            Text(message)
                .font(SNFont.secondary)
                .foregroundStyle(SNColor.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            actions
                .padding(.top, SNSpacing.xs)
        }
        .padding(SNSpacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

import SwiftUI

public struct SidebarDestinationRow: View {
    private let title: String
    private let symbol: String
    private let isSelected: Bool
    private let action: () -> Void
    @State private var isHovered = false

    public init(title: String, symbol: String, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: SNSpacing.s) {
                Image(systemName: symbol)
                    .frame(width: 20)
                    .accessibilityHidden(true)
                Text(title)
                Spacer(minLength: 0)
            }
            .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
            .foregroundStyle(isSelected ? SNColor.textPrimary : SNColor.textSecondary)
            .padding(.horizontal, SNSpacing.s)
            .padding(.vertical, 7)
            .background {
                if isSelected {
                    OrganicPillShape()
                        .fill(SNColor.card)
                        .overlay(OrganicPillShape().stroke(SNColor.borderSubtle, lineWidth: 1))
                } else if isHovered {
                    OrganicPillShape().fill(SNColor.borderSubtle.opacity(0.35))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

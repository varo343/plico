import SwiftUI

/// Icon-only switcher for the four destinations (labels appear on hover),
/// plus Settings. Replaces the sidebar. Concentric: container radius 12 with
/// 3 pt padding, items radius 9.
struct SectionSwitcher: View {
    @Binding var selection: SidebarDestination

    private static let radius: CGFloat = 12
    private static let padding: CGFloat = 3

    var body: some View {
        HStack(spacing: SNSpacing.xs) {
            HStack(spacing: 2) {
                ForEach(SidebarDestination.allCases) { destination in
                    item(destination)
                }
            }
            .padding(Self.padding)
            .background(SNColor.canvas, in: RoundedRectangle(cornerRadius: Self.radius))
            .overlay(RoundedRectangle(cornerRadius: Self.radius).stroke(SNColor.borderSubtle))

            Spacer(minLength: 0)

            SettingsLink {
                Image(systemName: "gearshape").font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(SNIconButtonStyle(size: CGSize(width: 30, height: 30)))
            .hoverLabel("Settings  ⌘,")
            .accessibilityLabel("Settings")
        }
    }

    private func item(_ destination: SidebarDestination) -> some View {
        let isSelected = selection == destination
        let innerRadius = Self.radius - Self.padding
        return Button { selection = destination } label: {
            Image(systemName: isSelected ? destination.selectedSymbol : destination.symbol)
                .font(.system(size: 13.5, weight: isSelected ? .semibold : .regular))
                .frame(width: 38, height: 28)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: innerRadius).fill(SNColor.card)
                            .overlay(RoundedRectangle(cornerRadius: innerRadius).stroke(SNColor.outline.opacity(0.85), lineWidth: 1.2))
                    }
                }
        }
        .buttonStyle(SNIconButtonStyle(shape: .rounded(innerRadius), size: CGSize(width: 38, height: 28)))
        .foregroundStyle(isSelected ? SNColor.textPrimary : SNColor.textSecondary)
        .hoverLabel("\(destination.title)  ⌘\(destination.shortcutNumber)")
        .accessibilityLabel(destination.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

extension SidebarDestination {
    var selectedSymbol: String {
        switch self {
        case .notes: "note.text"
        case .today: "sun.max.fill"
        case .mentions: "envelope.fill"
        case .trash: "trash.fill"
        }
    }

    var shortcutNumber: Int {
        (Self.allCases.firstIndex(of: self) ?? 0) + 1
    }
}

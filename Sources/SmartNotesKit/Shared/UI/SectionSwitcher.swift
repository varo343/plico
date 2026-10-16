import SwiftUI

/// Icon-only switcher for the sections. Hovering an icon morphs it into its
/// name. Concentric: container radius 10 with 3 pt padding → items radius 7.
struct SectionSwitcher: View {
    @Binding var selection: SidebarDestination
    @State private var hovered: SidebarDestination?
    @Namespace private var indicator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// `hovered` sets the initial hover state (used to render the morph).
    init(selection: Binding<SidebarDestination>, hovered: SidebarDestination? = nil) {
        _selection = selection
        _hovered = State(initialValue: hovered)
    }

    private static let radius: CGFloat = 10
    private static let padding: CGFloat = 3

    var body: some View {
        HStack(spacing: 1) {
            ForEach(SidebarDestination.allCases) { destination in
                item(destination)
            }
        }
        .padding(Self.padding)
        .background(SNColor.borderSubtle.opacity(0.45), in: RoundedRectangle(cornerRadius: Self.radius))
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: hovered)
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.75), value: selection)
    }

    private func item(_ destination: SidebarDestination) -> some View {
        let isSelected = selection == destination
        let showsName = hovered == destination
        let innerRadius = Self.radius - Self.padding
        return Button { selection = destination } label: {
            Group {
                if showsName {
                    Text(destination.title)
                        .font(.system(size: 12, weight: .semibold))
                        .fixedSize()
                        .padding(.horizontal, 10)
                        .transition(.opacity)
                } else {
                    Image(systemName: isSelected ? destination.selectedSymbol : destination.symbol)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                        .frame(width: 34)
                        .transition(.opacity)
                }
            }
            .frame(height: 26)
            .foregroundStyle(isSelected ? SNColor.textPrimary : SNColor.textSecondary)
            .background {
                if isSelected {
                    // Slides from the previous section to the new one.
                    RoundedRectangle(cornerRadius: innerRadius).fill(SNColor.card)
                        .shadow(color: .black.opacity(0.08), radius: 1.5, y: 1)
                        .matchedGeometryEffect(id: "selection", in: indicator)
                } else if showsName {
                    RoundedRectangle(cornerRadius: innerRadius).fill(SNColor.card.opacity(0.6))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: innerRadius))
        }
        .buttonStyle(SwitcherPressStyle())
        .onHover { inside in
            if inside { hovered = destination } else if hovered == destination { hovered = nil }
        }
        .help(destination.shortcutHint)
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
        case .settings: "gearshape.fill"
        }
    }

    var shortcutHint: String {
        switch self {
        case .settings: "Settings (⌘,)"
        default: "\(title) (⌘\((Self.primary.firstIndex(of: self) ?? 0) + 1))"
        }
    }
}

private struct SwitcherPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.snPressEffect(configuration.isPressed, scale: 0.92)
    }
}

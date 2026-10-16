import AppKit
import SwiftUI

/// The "/" command menu. Never takes keyboard focus: typing continues in the
/// block, and ↑/↓, Return, Tab and Esc are routed here by the text view.
struct SlashMenuView: View {
    let model: NoteEditorModel

    var body: some View {
        if let menu = model.slashMenu {
            SNFloatingSurface {
                VStack(alignment: .leading, spacing: 1) {
                    Text(menu.query.isEmpty ? "TURN INTO" : "TURN INTO · /\(menu.query)".uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(SNColor.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.top, 5)
                        .padding(.bottom, 3)
                    ForEach(Array(menu.commands.enumerated()), id: \.element.id) { index, command in
                        row(command, isHighlighted: index == menu.highlighted)
                    }
                    Text("↑↓ choose · ↩ apply · esc close")
                        .font(.system(size: 10))
                        .foregroundStyle(SNColor.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.top, 4)
                        .padding(.bottom, 3)
                }
                .frame(width: 230, alignment: .leading)
            }
            .fixedSize()
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Block commands")
        }
    }

    private func row(_ command: SlashCommand, isHighlighted: Bool) -> some View {
        let innerRadius = SNFloatingSurface<EmptyView>.radius - SNFloatingSurface<EmptyView>.padding
        return Button { model.applySlashCommand(command) } label: {
            HStack(spacing: SNSpacing.xs) {
                Image(systemName: command.type.symbol)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 24, height: 22)
                    .background(SNColor.canvas, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(SNColor.borderSubtle))
                Text(command.title).font(.system(size: 13, weight: .medium))
                Spacer()
                Text("/" + command.name).font(.system(size: 11)).foregroundStyle(SNColor.textSecondary)
            }
            .foregroundStyle(SNColor.textPrimary)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(isHighlighted ? SNColor.borderSubtle.opacity(0.85) : .clear, in: RoundedRectangle(cornerRadius: innerRadius))
            .contentShape(RoundedRectangle(cornerRadius: innerRadius))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(command.title)
        .accessibilityAddTraits(isHighlighted ? .isSelected : [])
    }
}

/// Shows/moves/hides the slash menu panel as the model's state changes.
struct SlashMenuPresenter: ViewModifier {
    let model: NoteEditorModel
    @State private var controller = FloatingPanelController()

    func body(content: Content) -> some View {
        content
            .onChange(of: model.slashMenu) { _, menu in
                guard let menu, let anchor = menu.anchor, let window = NSApp.keyWindow ?? NSApp.mainWindow else {
                    controller.close()
                    return
                }
                if controller.isShown {
                    controller.move(below: anchor)
                } else {
                    controller.onClose = nil
                    controller.show(SlashMenuView(model: model), below: anchor, in: window, acceptsKey: false)
                }
            }
            .onDisappear { controller.close() }
    }
}

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
                    ForEach(Array(menu.commands.enumerated()), id: \.element.id) { index, command in
                        // A header starts each group: block kinds, nested text, then tags.
                        if index == 0 || command.section != menu.commands[index - 1].section {
                            header(command.section.title, query: index == 0 ? menu.query : "")
                        }
                        row(command, isHighlighted: index == menu.highlighted)
                            .onHover { if $0 { model.highlightSlashCommand(at: index) } }
                    }
                    Text("↑↓ choose · ↩ apply · esc close")
                        .font(.system(size: 10))
                        .foregroundStyle(SNColor.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.top, 4)
                        .padding(.bottom, 3)
                }
                .frame(width: 230, alignment: .leading)
                .menuHighlight(on: menu.commands.indices.contains(menu.highlighted) ? menu.commands[menu.highlighted].id : nil)
            }
            .fixedSize()
            .modifier(PopIn())
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Block commands")
        }
    }

    private func header(_ title: String, query: String) -> some View {
        Text(query.isEmpty ? title : "\(title) · /\(query)".uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(SNColor.textSecondary)
            .padding(.horizontal, 10)
            .padding(.top, 5)
            .padding(.bottom, 3)
    }

    private func row(_ command: SlashCommand, isHighlighted: Bool) -> some View {
        let innerRadius = SNFloatingSurface<EmptyView>.radius - SNFloatingSurface<EmptyView>.padding
        return Button { model.applySlashCommand(command) } label: {
            HStack(spacing: SNSpacing.xs) {
                Image(systemName: command.symbol)
                    .font(.system(size: 12, weight: .medium))
                    .iconMotion(for: command.symbol, on: isHighlighted)
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
            .contentShape(RoundedRectangle(cornerRadius: innerRadius))
            .menuHighlightRow(command.id)
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

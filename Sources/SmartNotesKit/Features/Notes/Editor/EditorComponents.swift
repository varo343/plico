import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// In-app block drags. Private to the process, so text views and other apps
    /// never receive it (declared in the app's Info.plist).
    static let smartNotesBlock = UTType(exportedAs: "local.smartnotes.block")
}

/// Sends a formatting action to the focused block's text view.
@MainActor
enum EditorActions {
    static func send(_ selector: Selector) {
        NSApp.sendAction(selector, to: nil, from: nil)
    }

    static func toggle(_ mark: InlineMark) {
        switch mark {
        case .bold: send(#selector(BlockNSTextView.snToggleBold(_:)))
        case .italic: send(#selector(BlockNSTextView.snToggleItalic(_:)))
        case .underline: send(#selector(BlockNSTextView.snToggleUnderline(_:)))
        case .strikethrough: send(#selector(BlockNSTextView.snToggleStrikethrough(_:)))
        case .code: send(#selector(BlockNSTextView.snToggleCode(_:)))
        }
    }

    static func editLink() {
        send(#selector(BlockNSTextView.snEditLink(_:)))
    }
}

extension BlockType {
    var menuTitle: String {
        switch self {
        case .paragraph: "Body"
        case .heading1: "Heading 1"
        case .heading2: "Heading 2"
        case .heading3: "Heading 3"
        case .bulletItem: "Bulleted List"
        case .numberedItem: "Numbered List"
        case .checklistItem: "Checklist"
        case .quote: "Quote"
        }
    }
}

extension FontFamilyPreset {
    var menuTitle: String {
        switch self {
        case .system: "System"
        case .serif: "Serif"
        case .rounded: "Rounded"
        case .monospaced: "Monospaced"
        }
    }
}

/// Floating formatting pill. Appears while text is selected or when toggled
/// with "Aa". Highlights inside are capsules, concentric with the pill.
struct NoteEditorToolbar: View {
    let model: NoteEditorModel

    var body: some View {
        // Full bar when there's room; otherwise a compact bar whose extra
        // controls move into a "more" menu. Labels never wrap.
        ViewThatFits(in: .horizontal) {
            bar { fullControls }
            bar { compactControls }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Formatting")
    }

    private func bar<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 1) { content() }
            .foregroundStyle(SNColor.textPrimary)
            .padding(.horizontal, 4)
            .padding(.vertical, 3)
            .background(SNColor.card, in: Capsule())
            .overlay(Capsule().strokeBorder(SNColor.borderSubtle, lineWidth: 1))
            .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
            .fixedSize()
    }

    @ViewBuilder
    private var fullControls: some View {
        blockTypeMenu
        blockButton(.checklistItem, symbol: "checklist", label: "Checklist", shortcut: "⇧⌘L")
        blockButton(.bulletItem, symbol: "list.bullet", label: "Bulleted list", shortcut: "⇧⌘7")
        blockButton(.numberedItem, symbol: "list.number", label: "Numbered list", shortcut: "⇧⌘8")
        divider
        markButtons
        divider
        fontMenu
        sizeMenu
    }

    @ViewBuilder
    private var compactControls: some View {
        blockTypeMenu
        divider
        markButton(.bold, symbol: "bold", label: "Bold", shortcut: "⌘B")
        markButton(.italic, symbol: "italic", label: "Italic", shortcut: "⌘I")
        markButton(.underline, symbol: "underline", label: "Underline", shortcut: "⌘U")
        linkButton
        moreMenu
    }

    @ViewBuilder
    private var markButtons: some View {
        markButton(.bold, symbol: "bold", label: "Bold", shortcut: "⌘B")
        markButton(.italic, symbol: "italic", label: "Italic", shortcut: "⌘I")
        markButton(.underline, symbol: "underline", label: "Underline", shortcut: "⌘U")
        markButton(.strikethrough, symbol: "strikethrough", label: "Strikethrough", shortcut: "⇧⌘X")
        markButton(.code, symbol: "chevron.left.forwardslash.chevron.right", label: "Inline code", shortcut: nil)
        linkButton
    }

    private var linkButton: some View {
        Button { EditorActions.editLink() } label: { icon("link") }
            .buttonStyle(SNIconButtonStyle(shape: .capsule))
            .hoverLabel("Link  ⌘K")
            .accessibilityLabel("Link")
    }

    /// Compact bar: everything that didn't fit, in one menu.
    private var moreMenu: some View {
        SNDropdown(minWidth: 210, shape: .capsule, showsChevron: false) {
            let family = model.selectionFontFamily
            let size = model.selectionFontSize
            return [.header("Blocks")]
                + [BlockType.checklistItem, .bulletItem, .numberedItem].map { type in
                    .item(SNMenuItem(title: type.menuTitle, icon: type.symbol, isChecked: model.activeBlock?.type == type) {
                        model.setBlockType(model.activeBlock?.type == type ? .paragraph : type)
                    })
                }
                + [.divider(),
                   .item(SNMenuItem(title: "Strikethrough", icon: "strikethrough", shortcut: "⇧⌘X") { EditorActions.toggle(.strikethrough) }),
                   .item(SNMenuItem(title: "Inline code", icon: "chevron.left.forwardslash.chevron.right") { EditorActions.toggle(.code) }),
                   .header("Font")]
                + FontFamilyPreset.allCases.map { option in
                    .item(SNMenuItem(title: option.menuTitle, icon: option.symbol, isChecked: family == option) { model.setFontFamily(option) })
                }
                + [.header("Size")]
                + FontSizePreset.allCases.map { option in
                    .item(SNMenuItem(title: "\(option.rawValue) pt", isChecked: size == option) { model.setFontSize(option) })
                }
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 12, weight: .semibold))
        }
        .hoverLabel("More formatting")
        .accessibilityLabel("More formatting")
    }

    private var divider: some View {
        Rectangle().fill(SNColor.borderSubtle).frame(width: 1, height: 18).padding(.horizontal, 4)
    }

    private func icon(_ symbol: String) -> some View {
        Image(systemName: symbol).font(.system(size: 12.5, weight: .semibold))
    }

    private func markButton(_ mark: InlineMark, symbol: String, label: String, shortcut: String?) -> some View {
        let isOn = model.selectionMarks.contains(mark) && model.hasTextSelection
        return Button { EditorActions.toggle(mark) } label: { icon(symbol) }
            .buttonStyle(SNIconButtonStyle(isActive: isOn, shape: .capsule))
            .hoverLabel(shortcut.map { "\(label)  \($0)" } ?? label)
            .accessibilityLabel(label)
            .accessibilityValue(isOn ? "On" : "Off")
    }

    /// One-click block kinds; clicking the active kind turns the block back into text.
    private func blockButton(_ type: BlockType, symbol: String, label: String, shortcut: String) -> some View {
        let isOn = model.activeBlock?.type == type
        return Button { model.setBlockType(isOn ? .paragraph : type) } label: { icon(symbol) }
            .buttonStyle(SNIconButtonStyle(isActive: isOn, shape: .capsule))
            .hoverLabel("\(label)  \(shortcut)  ·  /\(type.slashName)")
            .accessibilityLabel(label)
            .accessibilityValue(isOn ? "On" : "Off")
    }

    private var blockTypeMenu: some View {
        SNDropdown(minWidth: 210, shape: .capsule) {
            [.header("Turn into")] + BlockType.allCases.map { type in
                .item(SNMenuItem(title: type.menuTitle, icon: type.symbol, isChecked: model.activeBlock?.type == type,
                                 shortcut: "/" + type.slashName) { model.setBlockType(type) })
            }
        } label: {
            // Never wraps: long names ("Bulleted list") truncate with an ellipsis.
            Text(model.activeBlock?.type.menuTitle ?? "Body")
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 84, alignment: .leading)
        }
        .hoverLabel("Block type")
        .accessibilityLabel("Block type")
    }

    private var fontMenu: some View {
        SNDropdown(minWidth: 180, shape: .capsule) {
            let current = model.selectionFontFamily
            return [.header("Font")]
                + [.item(SNMenuItem(title: "Default", icon: "textformat", isChecked: current == nil) { model.setFontFamily(nil) })]
                + FontFamilyPreset.allCases.map { family in
                    .item(SNMenuItem(title: family.menuTitle, icon: family.symbol, isChecked: current == family) { model.setFontFamily(family) })
                }
        } label: {
            Text("Font").font(.system(size: 12, weight: .medium))
        }
        .hoverLabel("Font · selection or whole block")
        .accessibilityLabel("Font")
    }

    private var sizeMenu: some View {
        SNDropdown(minWidth: 150, shape: .capsule) {
            let current = model.selectionFontSize
            return [.header("Size")]
                + [.item(SNMenuItem(title: "Default", isChecked: current == nil) { model.setFontSize(nil) })]
                + FontSizePreset.allCases.map { size in
                    .item(SNMenuItem(title: "\(size.rawValue) pt", isChecked: current == size) { model.setFontSize(size) })
                }
        } label: {
            Text("Size").font(.system(size: 12, weight: .medium))
        }
        .hoverLabel("Text size · selection or whole block")
        .accessibilityLabel("Text size")
    }
}

extension BlockType {
    var symbol: String {
        switch self {
        case .paragraph: "text.alignleft"
        case .heading1: "textformat.size.larger"
        case .heading2: "textformat.size"
        case .heading3: "textformat.size.smaller"
        case .bulletItem: "list.bullet"
        case .numberedItem: "list.number"
        case .checklistItem: "checklist"
        case .quote: "text.quote"
        }
    }

    /// The slash command that turns a block into this kind.
    var slashName: String {
        SlashCommand.all.first { $0.type == self }?.name ?? rawValue
    }
}

extension FontFamilyPreset {
    var symbol: String {
        switch self {
        case .system: "character"
        case .serif: "character.book.closed"
        case .rounded: "circle.dashed"
        case .monospaced: "chevron.left.forwardslash.chevron.right"
        }
    }
}

/// Grip shown on block hover. Drag to reorder; right-click or VoiceOver
/// actions provide Move Up / Move Down without dragging.
struct BlockDragHandle: View {
    let isVisible: Bool
    let height: CGFloat
    let moveUp: () -> Void
    let moveDown: () -> Void

    var body: some View {
        Image(systemName: "circle.grid.2x3.fill")
            .font(.system(size: 9))
            .foregroundStyle(SNColor.textSecondary)
            .frame(width: 18, height: height)
            .contentShape(Rectangle())
            .opacity(isVisible ? 1 : 0)
            .help("Drag to move this block. Right-click for more.")
            .contextMenu {
                Button("Move Up", action: moveUp)
                Button("Move Down", action: moveDown)
            }
            .accessibilityLabel("Move block")
            .accessibilityAction(named: "Move Up", moveUp)
            .accessibilityAction(named: "Move Down", moveDown)
    }
}

/// Line showing where a dragged block will land.
struct BlockInsertionIndicator: View {
    var body: some View {
        HStack(spacing: 0) {
            Circle().stroke(SNColor.focusRing, lineWidth: 2).frame(width: 7, height: 7)
            Rectangle().fill(SNColor.focusRing).frame(height: 2)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// ⌘K sheet. Only web and mail addresses are accepted.
struct LinkEditorSheet: View {
    @Bindable var model: NoteEditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: SNSpacing.s) {
            Text(model.linkDraft?.hasExistingLink == true ? "Edit Link" : "Add Link").font(SNFont.section)
            TextField("https://example.com", text: Binding(
                get: { model.linkDraft?.url ?? "" },
                set: { model.linkDraft?.url = $0; model.linkError = nil }
            ))
            .textFieldStyle(.roundedBorder)
            .frame(width: 340)
            .onSubmit { model.commitLink() }
            .accessibilityLabel("Link address")
            if let error = model.linkError {
                Text(error).font(SNFont.secondary).foregroundStyle(SNColor.textPrimary)
                    .padding(SNSpacing.xs)
                    .background(SNColor.accentCoral, in: RoundedRectangle(cornerRadius: 6))
            }
            HStack {
                if model.linkDraft?.hasExistingLink == true {
                    Button("Remove Link", role: .destructive) { model.removeLink() }
                }
                Spacer()
                Button("Cancel") { model.cancelLinkEditing() }
                    .keyboardShortcut(.cancelAction)
                Button("Apply") { model.commitLink() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(SNSpacing.l)
    }
}

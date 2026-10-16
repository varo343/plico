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
/// from the window toolbar. Essential formatting also has keyboard shortcuts.
struct NoteEditorToolbar: View {
    let model: NoteEditorModel

    var body: some View {
        HStack(spacing: 2) {
            blockTypeMenu
            divider
            markButton(.bold, symbol: "bold", label: "Bold", shortcut: "⌘B")
            markButton(.italic, symbol: "italic", label: "Italic", shortcut: "⌘I")
            markButton(.underline, symbol: "underline", label: "Underline", shortcut: "⌘U")
            markButton(.strikethrough, symbol: "strikethrough", label: "Strikethrough", shortcut: "⇧⌘X")
            markButton(.code, symbol: "chevron.left.forwardslash.chevron.right", label: "Inline Code", shortcut: nil)
            Button { EditorActions.editLink() } label: { icon("link") }
                .help("Link (⌘K)")
                .accessibilityLabel("Link")
            divider
            fontMenu
            sizeMenu
        }
        .buttonStyle(.plain)
        .foregroundStyle(SNColor.textPrimary)
        .padding(.horizontal, SNSpacing.xs)
        .padding(.vertical, 5)
        .background(SNColor.card, in: Capsule())
        .overlay(Capsule().stroke(SNColor.outline.opacity(0.8), lineWidth: 1.5))
        .shadow(color: .black.opacity(0.14), radius: 10, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Formatting")
    }

    private var divider: some View {
        Rectangle().fill(SNColor.borderSubtle).frame(width: 1, height: 18).padding(.horizontal, 4)
    }

    private func icon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 12.5, weight: .semibold))
            .frame(width: 28, height: 26)
            .contentShape(Rectangle())
    }

    private func markButton(_ mark: InlineMark, symbol: String, label: String, shortcut: String?) -> some View {
        let isOn = model.selectionMarks.contains(mark) && model.hasTextSelection
        return Button { EditorActions.toggle(mark) } label: {
            icon(symbol)
                .background(isOn ? SNColor.borderSubtle : .clear, in: RoundedRectangle(cornerRadius: 7))
        }
        .help(shortcut.map { "\(label) (\($0))" } ?? label)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "On" : "Off")
    }

    private var blockTypeMenu: some View {
        Menu {
            ForEach(BlockType.allCases, id: \.self) { type in
                Button(type.menuTitle) { model.setBlockType(type) }
            }
        } label: {
            Text(model.activeBlock?.type.menuTitle ?? "Body").font(.system(size: 12, weight: .semibold))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .padding(.horizontal, 6)
        .help("Block type")
        .accessibilityLabel("Block type")
    }

    private var fontMenu: some View {
        Menu {
            Button("Default") { model.setFontFamily(nil) }
            ForEach(FontFamilyPreset.allCases, id: \.self) { family in
                Button(family.menuTitle) { model.setFontFamily(family) }
            }
        } label: {
            Text("Font").font(.system(size: 12, weight: .medium))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .padding(.horizontal, 4)
        .help("Font (applies to selection, or the whole block)")
        .accessibilityLabel("Font")
    }

    private var sizeMenu: some View {
        Menu {
            Button("Default") { model.setFontSize(nil) }
            ForEach(FontSizePreset.allCases, id: \.self) { size in
                Button("\(size.rawValue) pt") { model.setFontSize(size) }
            }
        } label: {
            Text("Size").font(.system(size: 12, weight: .medium))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .padding(.horizontal, 4)
        .help("Text size (applies to selection, or the whole block)")
        .accessibilityLabel("Text size")
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

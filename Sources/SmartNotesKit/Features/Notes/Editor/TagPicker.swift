import AppKit
import SwiftUI

/// Trailing end of a block: its tag (click to change), or, on row hover, a
/// tag button that opens the picker. The slot is always reserved so the text
/// doesn't reflow when the button appears.
struct BlockTagControl: View {
    let tag: BlockTag?
    let blockID: UUID
    let model: NoteEditorModel
    let isRowHovered: Bool
    /// The row has the caret: the picker can open from the keyboard or "/tag".
    var isRowActive = false
    @State private var controller = FloatingPanelController()
    @State private var anchor = AnchorBox()
    @State private var isOpen = false
    /// Opening was asked for before the anchor was there (see `open`).
    @State private var wantsAnchor = false

    var body: some View {
        Group {
            if let tag {
                Button { isOpen ? controller.close() : open() } label: { BlockTagBadge(tag: tag) }
                    .buttonStyle(SNBadgeButtonStyle(isActive: isOpen))
                    .frame(minWidth: 28, minHeight: 26)
            } else {
                Button { isOpen ? controller.close() : open() } label: {
                    MotionIcon(symbol: "tag", size: 11.5)
                        .foregroundStyle(SNColor.textSecondary)
                }
                .buttonStyle(SNIconButtonStyle(isActive: isOpen, shape: .capsule))
            }
        }
        // Hidden, not removed, when untagged and not hovered: the slot stays put.
        .opacity(tag != nil || isRowHovered || isOpen ? 1 : 0)
        .allowsHitTesting(tag != nil || isRowHovered || isOpen)
        .snAnimation(SNMotion.hover, value: isRowHovered)
        // Where the picker opens from; only where it can open (hover, caret),
        // as an AppKit view in every row slowed the editor down.
        .background { if isRowHovered || isRowActive || isOpen || wantsAnchor { AnchorReader(box: anchor) } }
        .hoverLabel(tag == nil ? "Add tag" : "Change tag")
        .accessibilityLabel(tag.map { "Tag: \($0.label)" } ?? "Add tag")
        .onChange(of: model.tagPickerRequest) { _, request in
            guard request?.blockID == blockID else { return }
            model.tagPickerRequest = nil
            open()
        }
        .onDisappear { controller.close() }
    }

    private func open(retries: Int = 5) {
        guard let window = anchor.view?.window, let rect = anchor.screenRect else {
            // No anchor yet (a click without hovering first, e.g. from a
            // tablet or VoiceOver): add it, and open once it's in place.
            wantsAnchor = true
            if retries > 0 { DispatchQueue.main.async { open(retries: retries - 1) } }
            return
        }
        wantsAnchor = false
        controller.onClose = { isOpen = false }
        let picker = TagPicker(current: tag, suggestions: model.customTagSuggestions) { choice in
            controller.close()
            if let choice { model.setBlockTag(choice.tag, blockID: blockID) } else { model.refocusBlock(blockID) }
        }
        controller.show(SNFloatingSurface { picker }.fixedSize().modifier(PopIn()),
                        below: rect, in: window, acceptsKey: true, alignsTrailing: true)
        isOpen = true
    }
}

/// High / Medium / Low, a custom name, tags already used in the note, Remove.
/// Typing "high", "medium" or "low" picks that priority too.
struct TagPicker: View {
    /// What the picker ended with; `nil` = closed without a change (Esc).
    struct Choice { var tag: BlockTag? }

    let current: BlockTag?
    let suggestions: [String]
    let finish: (Choice?) -> Void
    @State private var name = ""
    @FocusState private var fieldFocused: Bool

    private static let width: CGFloat = 228

    var body: some View {
        VStack(alignment: .leading, spacing: SNSpacing.xs) {
            sectionTitle("TAG")
            HStack(spacing: 6) {
                ForEach([Priority.high, .medium, .low], id: \.self) { priority in
                    choiceButton(.priority(priority)) { PriorityBadge(priority) }
                }
            }
            .padding(.horizontal, 6)

            TextField("Custom tag…", text: $name)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($fieldFocused)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(SNColor.canvas, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(fieldFocused ? SNColor.focusRing : SNColor.borderSubtle, lineWidth: 1))
                .padding(.horizontal, 6)
                .onChange(of: name) { _, value in
                    if value.count > BlockTag.maxCustomLength { name = String(value.prefix(BlockTag.maxCustomLength)) }
                }
                .onSubmit {
                    // An empty name changes nothing.
                    finish(BlockTag.named(name).map { Choice(tag: $0) })
                }
                .accessibilityLabel("Custom tag name")

            if !suggestions.isEmpty {
                sectionTitle("IN THIS NOTE")
                FlowLayout(spacing: 6) {
                    ForEach(suggestions, id: \.self) { suggestion in
                        choiceButton(.custom(suggestion)) { SNBadge(text: suggestion, size: .small) }
                    }
                }
                .padding(.horizontal, 6)
            }

            if current != nil {
                Rectangle().fill(SNColor.borderSubtle).frame(height: 1).padding(.horizontal, 6)
                RemoveTagRow { finish(Choice(tag: nil)) }
            }

            Text("↩ apply · esc close")
                .font(.system(size: 10))
                .foregroundStyle(SNColor.textSecondary)
                .padding(.horizontal, 10)
                .padding(.bottom, 3)
        }
        .padding(.top, 5)
        .frame(width: Self.width, alignment: .leading)
        .onAppear {
            if case .custom(let existing)? = current { name = existing }
            fieldFocused = true
        }
        .onExitCommand { finish(nil) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tag")
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(SNColor.textSecondary)
            .padding(.horizontal, 10)
    }

    /// A badge you can click; the block's current tag is ringed.
    private func choiceButton<Badge: View>(_ tag: BlockTag, @ViewBuilder badge: () -> Badge) -> some View {
        Button { finish(Choice(tag: tag)) } label: {
            badge()
                .padding(3)
                .overlay {
                    if current == tag {
                        WobblyCapsuleShape(variant: 1, amplitude: 1.2).stroke(SNColor.outline, lineWidth: 1.5)
                    }
                }
        }
        .buttonStyle(SNBadgeButtonStyle())
        .accessibilityLabel(tag.label)
        .accessibilityAddTraits(current == tag ? .isSelected : [])
    }
}

private struct RemoveTagRow: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        let radius = SNFloatingSurface<EmptyView>.radius - SNFloatingSurface<EmptyView>.padding
        Button(action: action) {
            HStack(spacing: SNSpacing.xs) {
                MotionIcon(symbol: "tag.slash", size: 12)
                    .frame(width: 24, height: 22)
                Text("Remove tag").font(.system(size: 13, weight: .medium))
                Spacer()
            }
            .foregroundStyle(SNColor.textPrimary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(isHovered ? SNColor.borderSubtle.opacity(0.85) : .clear, in: RoundedRectangle(cornerRadius: radius))
            .contentShape(RoundedRectangle(cornerRadius: radius))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

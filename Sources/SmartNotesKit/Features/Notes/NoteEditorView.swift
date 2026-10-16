import SwiftUI

/// Title + block body for one note. Minimal chrome; writing comes first.
struct NoteEditorView: View {
    @Bindable var model: NoteEditorModel
    var defaults = EditorDefaults()

    var body: some View {
        VStack(spacing: 0) {
            if let error = model.saveError {
                SaveErrorBanner(message: error) { model.flush() }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: SNSpacing.m) {
                    TextField("Title", text: Binding(get: { model.note.title }, set: model.setTitle), axis: .vertical)
                        .font(SNFont.title)
                        .foregroundStyle(SNColor.textPrimary)
                        .textFieldStyle(.plain)
                        .onSubmit { model.focusFirstBlock() }
                        .accessibilityLabel("Note title")

                    // Not lazy: recycling rows would recreate a text view while it
                    // is being edited, losing focus and undo history.
                    VStack(alignment: .leading, spacing: SNSpacing.xxs) {
                        let numbers = listNumbers(model.note.blocks)
                        ForEach(Array(model.note.blocks.enumerated()), id: \.element.id) { index, block in
                            BlockRow(
                                block: block,
                                number: numbers[index],
                                defaults: defaults,
                                focusRequest: model.focusRequest,
                                model: model
                            )
                        }
                    }

                    // Clicking below the last block continues writing there.
                    Color.clear
                        .frame(maxWidth: .infinity, minHeight: 160)
                        .contentShape(Rectangle())
                        .onTapGesture { model.focusLastBlockEnd() }
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, SNSpacing.xl + SNSpacing.xs)
                .padding(.top, SNSpacing.l)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            // Keeps the floating New Note button clear of the last lines.
            .contentMargins(.bottom, 96, for: .scrollContent)
        }
        .background(SNColor.canvas)
    }

    /// 1-based numbers for consecutive numbered items at the same indent.
    private func listNumbers(_ blocks: [NoteBlock]) -> [Int?] {
        var counters: [Int: Int] = [:]
        return blocks.map { block in
            guard block.type == .numberedItem else {
                counters.removeAll()
                return nil
            }
            counters = counters.filter { $0.key <= block.indentLevel }
            let next = (counters[block.indentLevel] ?? 0) + 1
            counters[block.indentLevel] = next
            return next
        }
    }
}

private struct BlockRow: View {
    let block: NoteBlock
    let number: Int?
    let defaults: EditorDefaults
    let focusRequest: FocusRequest?
    let model: NoteEditorModel

    private static let indentWidth: CGFloat = 22
    private static let gutterWidth: CGFloat = 24

    var body: some View {
        let style = BlockTextStyle(type: block.type, defaults: defaults, isChecked: block.isChecked)
        HStack(alignment: .top, spacing: SNSpacing.xxs) {
            gutter(style: style)
            BlockTextView(
                content: block.content,
                style: style,
                accessibilityLabel: accessibilityLabel,
                focusRequest: focusRequest,
                blockID: block.id,
                actions: BlockTextActions(
                    onChange: { [model, id = block.id] in model.setContent($0, ofBlock: id) },
                    onEnter: { [model, id = block.id] in model.splitBlock(id, atUTF16Offset: $0) },
                    onBackspaceAtStart: { [model, id = block.id] in model.mergeBlockWithPrevious(id) },
                    onExitUp: { [model, id = block.id] in model.focusPrevious(before: id) },
                    onExitDown: { [model, id = block.id] in model.focusNext(after: id) }
                )
            )
        }
        .padding(.leading, CGFloat(block.indentLevel) * Self.indentWidth)
        .padding(.top, block.type.isHeading ? SNSpacing.xs : 0)
    }

    @ViewBuilder
    private func gutter(style: BlockTextStyle) -> some View {
        Group {
            switch block.type {
            case .bulletItem:
                Text("•").font(.system(size: style.baseSize, weight: .bold))
                    .foregroundStyle(SNColor.textSecondary)
                    .accessibilityHidden(true)
            case .numberedItem:
                Text("\(number ?? 1).").font(.system(size: style.baseSize).monospacedDigit())
                    .foregroundStyle(SNColor.textSecondary)
                    .accessibilityHidden(true)
            case .checklistItem:
                Button { model.toggleChecked(block.id) } label: {
                    Image(systemName: block.isChecked ? "checkmark.square.fill" : "square")
                        .font(.system(size: style.baseSize))
                        .foregroundStyle(block.isChecked ? SNColor.focusRing : SNColor.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Checklist item")
                .accessibilityValue(block.isChecked ? "Checked" : "Unchecked")
            case .quote:
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(SNColor.borderSubtle)
                    .frame(width: 3)
                    .accessibilityHidden(true)
            default:
                EmptyView()
            }
        }
        .frame(width: block.type.hasGutter ? Self.gutterWidth : 0, height: style.lineHeight, alignment: block.type == .quote ? .center : .leading)
    }

    private var accessibilityLabel: String {
        switch block.type {
        case .heading1: "Heading 1"
        case .heading2: "Heading 2"
        case .heading3: "Heading 3"
        case .bulletItem: "Bulleted item"
        case .numberedItem: "Numbered item \(number ?? 1)"
        case .checklistItem: "Checklist item"
        case .quote: "Quote"
        case .paragraph: "Paragraph"
        }
    }
}

private struct SaveErrorBanner: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        HStack(spacing: SNSpacing.s) {
            Image(systemName: "exclamationmark.triangle.fill").accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Couldn't save this note").font(SNFont.rowTitle)
                Text("Your changes are kept in this window. \(message)").font(SNFont.secondary)
            }
            Spacer()
            Button("Retry", action: retry)
        }
        .foregroundStyle(SNColor.textPrimary)
        .padding(SNSpacing.s)
        .background(SNColor.accentCoral)
        .accessibilityElement(children: .combine)
    }
}

extension BlockType {
    var isHeading: Bool { self == .heading1 || self == .heading2 || self == .heading3 }
    var hasGutter: Bool { isListLike || self == .quote }
}

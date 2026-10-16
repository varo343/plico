import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Title + block body for one note. Minimal chrome; writing comes first.
struct NoteEditorView: View {
    @Bindable var model: NoteEditorModel
    /// Supplies the metadata strip; nil hides it (e.g. in tests).
    var notes: NotesModel?
    var defaults = EditorDefaults()
    @State private var draggingBlockID: UUID?
    @State private var dropTarget: DropTarget?

    var body: some View {
        VStack(spacing: 0) {
            if let error = model.saveError {
                SaveErrorBanner(message: error, retry: { model.flush() }, copy: {
                    // Recovery path: get the text out even if the store keeps failing.
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(NoteExport.markdown(model.note), forType: .string)
                })
            }
            ScrollView {
                VStack(alignment: .leading, spacing: SNSpacing.m) {
                    TextField("Title", text: Binding(get: { model.note.title }, set: model.setTitle), axis: .vertical)
                        .font(SNFont.title)
                        .foregroundStyle(SNColor.textPrimary)
                        .textFieldStyle(.plain)
                        .onSubmit { model.focusFirstBlock() }
                        .accessibilityLabel("Note title")

                    if let notes {
                        NoteMetadataStrip(noteID: model.note.id, notes: notes)
                    }

                    // Not lazy: recycling rows would recreate a text view while it
                    // is being edited, losing focus and in-progress input.
                    VStack(alignment: .leading, spacing: SNSpacing.xxs) {
                        let numbers = listNumbers(model.note.blocks)
                        ForEach(Array(model.note.blocks.enumerated()), id: \.element.id) { index, block in
                            BlockRow(
                                block: block,
                                number: numbers[index],
                                defaults: defaults,
                                focusRequest: model.focusRequest,
                                model: model,
                                draggingBlockID: $draggingBlockID,
                                dropTarget: $dropTarget
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
        // Floating formatting bar: shown on selection or via the toolbar toggle.
        // It overlays (never pushes) text, and stays clear of the New Note button.
        .overlay(alignment: .bottom) {
            if model.hasTextSelection || model.showsFormattingBar {
                NoteEditorToolbar(model: model)
                    .padding(.leading, SNSpacing.m)
                    .padding(.trailing, 104)
                    .padding(.bottom, SNSpacing.l)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.12), value: model.hasTextSelection || model.showsFormattingBar)
        .sheet(isPresented: Binding(get: { model.linkDraft != nil }, set: { if !$0 { model.cancelLinkEditing() } })) {
            LinkEditorSheet(model: model)
        }
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

/// Where a dragged block or note will land.
struct DropTarget: Equatable {
    var itemID: UUID
    var placeAfter: Bool
}

private struct BlockRow: View {
    let block: NoteBlock
    let number: Int?
    let defaults: EditorDefaults
    let focusRequest: FocusRequest?
    let model: NoteEditorModel
    @Binding var draggingBlockID: UUID?
    @Binding var dropTarget: DropTarget?
    @State private var isHovered = false
    @State private var rowHeight: CGFloat = 0

    private static let indentWidth: CGFloat = 22
    private static let gutterWidth: CGFloat = 24
    /// Handle (18) + spacing (6) live in the editor's left margin, so block text
    /// stays aligned with the title and nothing shifts when the handle appears.
    private static let handleSpace: CGFloat = 24

    var body: some View {
        let style = BlockTextStyle(type: block.type, defaults: defaults, isChecked: block.isChecked)
        HStack(alignment: .top, spacing: 6) {
            BlockDragHandle(
                isVisible: isHovered,
                height: style.lineHeight,
                moveUp: { model.moveBlock(block.id, by: -1) },
                moveDown: { model.moveBlock(block.id, by: 1) }
            )
            .onDrag {
                draggingBlockID = block.id
                let provider = NSItemProvider()
                provider.registerDataRepresentation(forTypeIdentifier: UTType.smartNotesBlock.identifier, visibility: .ownProcess) { completion in
                    completion(Data(block.id.uuidString.utf8), nil)
                    return nil
                }
                return provider
            } preview: {
                Text(block.content.plainText.isEmpty ? " " : String(block.content.plainText.prefix(60)))
                    .font(SNFont.body)
                    .padding(SNSpacing.xs)
                    .background(SNColor.card, in: RoundedRectangle(cornerRadius: SNRadius.small))
            }

            HStack(alignment: .top, spacing: SNSpacing.xxs) {
                gutter(style: style)
                BlockTextView(
                    content: block.content,
                    style: style,
                    accessibilityLabel: accessibilityLabel,
                    focusRequest: focusRequest,
                    blockID: block.id,
                    actions: actions
                )
            }
            .padding(.leading, CGFloat(block.indentLevel) * Self.indentWidth)
        }
        .padding(.leading, -Self.handleSpace)
        .padding(.top, block.type.isHeading ? SNSpacing.xs : 0)
        .onHover { isHovered = $0 }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { rowHeight = $0 }
        .overlay(alignment: dropTarget?.placeAfter == true ? .bottom : .top) {
            if dropTarget?.itemID == block.id {
                BlockInsertionIndicator().offset(y: dropTarget?.placeAfter == true ? 3 : -3)
            }
        }
        .onDrop(of: [.smartNotesBlock], delegate: BlockDropDelegate(
            blockID: block.id, rowHeight: rowHeight, model: model,
            draggingBlockID: $draggingBlockID, dropTarget: $dropTarget
        ))
    }

    private var actions: BlockTextActions {
        let id = block.id
        return BlockTextActions(
            onChange: { [model] in model.setContent($0, ofBlock: id) },
            onSelectionChange: { [model] in model.updateSelection(blockID: id, range: $0) },
            onEnter: { [model] in model.splitBlock(id, atUTF16Offset: $0) },
            onBackspaceAtStart: { [model] in model.mergeBlockWithPrevious(id) },
            onExitUp: { [model] in model.focusPrevious(before: id) },
            onExitDown: { [model] in model.focusNext(after: id) },
            onIndent: { [model] in model.indentBlock(id, by: $0) },
            onToggleMark: { [model] in model.toggleMark($0, blockID: id, range: $1) },
            onEditLink: { [model] in model.beginLinkEditing(blockID: id, range: $0) },
            onPaste: { [model] in model.paste($0, blockID: id, range: $1) },
            onMoveBlock: { [model] in model.moveBlock(id, by: $0) },
            onUndo: { [model] in model.undo() },
            onRedo: { [model] in model.redo() },
            canUndo: { [model] in model.canUndo },
            canRedo: { [model] in model.canRedo }
        )
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

/// Shows the insertion line and moves the dragged block on drop.
private struct BlockDropDelegate: DropDelegate {
    let blockID: UUID
    let rowHeight: CGFloat
    let model: NoteEditorModel
    @Binding var draggingBlockID: UUID?
    @Binding var dropTarget: DropTarget?

    func validateDrop(info: DropInfo) -> Bool {
        draggingBlockID != nil && info.hasItemsConforming(to: [.smartNotesBlock])
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        let target = DropTarget(itemID: blockID, placeAfter: info.location.y > rowHeight / 2)
        if dropTarget != target { dropTarget = target }
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        if dropTarget?.itemID == blockID { dropTarget = nil }
    }

    func performDrop(info: DropInfo) -> Bool {
        defer {
            draggingBlockID = nil
            dropTarget = nil
        }
        guard let dragged = draggingBlockID else { return false }
        model.moveBlock(dragged, relativeTo: blockID, placeAfter: info.location.y > rowHeight / 2)
        return true
    }
}

private struct SaveErrorBanner: View {
    let message: String
    let retry: () -> Void
    let copy: () -> Void

    var body: some View {
        HStack(spacing: SNSpacing.s) {
            Image(systemName: "exclamationmark.triangle.fill").accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Couldn't save this note").font(SNFont.rowTitle)
                Text("Your changes are kept in this window. \(message)").font(SNFont.secondary)
            }
            Spacer()
            Button("Copy as Text", action: copy)
                .help("Copy this note as Markdown so nothing is lost")
            Button("Retry", action: retry)
                .keyboardShortcut(.defaultAction)
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

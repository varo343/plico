import AppKit
import SwiftUI

/// Title + block body for one note. Minimal chrome; writing comes first.
struct NoteEditorView: View {
    @Bindable var model: NoteEditorModel
    /// Supplies the metadata strip; nil hides it (e.g. in tests).
    var notes: NotesModel?
    var defaults = EditorDefaults()
    @State private var drag: BlockDrag?
    @State private var dropTarget: DropTarget?
    @State private var blockFrames: [UUID: CGRect] = [:]

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
                                drag: drag,
                                dropTarget: dropTarget,
                                onDragChanged: { dragChanged(block.id, $0) },
                                onDragEnded: { dragEnded(block.id) }
                            )
                            .background(GeometryReader { proxy in
                                Color.clear.preference(key: BlockFramesKey.self, value: [block.id: proxy.frame(in: .named(Self.blocksSpace))])
                            })
                            .zIndex(drag?.blockID == block.id ? 1 : 0)
                        }
                    }
                    .coordinateSpace(name: Self.blocksSpace)
                    .onPreferenceChange(BlockFramesKey.self) { blockFrames = $0 }
                    .snAnimation(SNMotion.snappy, value: model.note.blocks.map(\.id))

                    // Clicking below the last block continues writing there. Its height
                    // also lets the last line scroll clear of the New Note button.
                    Color.clear
                        .frame(maxWidth: .infinity, minHeight: 200)
                        .contentShape(Rectangle())
                        .onTapGesture { model.focusLastBlockEnd() }
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, SNSpacing.xl + SNSpacing.xs)
                .padding(.top, SNSpacing.xxs)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .modifier(SlashMenuPresenter(model: model))
        .sheet(isPresented: Binding(get: { model.linkDraft != nil }, set: { if !$0 { model.cancelLinkEditing() } })) {
            LinkEditorSheet(model: model)
        }
    }

    // MARK: Block drag

    private static let blocksSpace = "SmartNotes.blocks"

    private func dragChanged(_ id: UUID, _ value: DragGesture.Value) {
        if drag?.blockID != id {
            drag = BlockDrag(blockID: id, startY: value.startLocation.y, currentY: value.location.y)
            NSCursor.closedHand.push()
        } else {
            drag?.currentY = value.location.y
        }
        let ordered = model.note.blocks.compactMap { block in blockFrames[block.id].map { (id: block.id, frame: $0) } }
        let target = DropResolver.target(pointerY: value.location.y, frames: ordered, dragged: id)
        let newTarget = target.map { DropTarget(itemID: $0.id, placeAfter: $0.placeAfter) }
        if newTarget != dropTarget { dropTarget = newTarget }
    }

    private func dragEnded(_ id: UUID) {
        if let target = dropTarget {
            model.moveBlock(id, relativeTo: target.itemID, placeAfter: target.placeAfter)
        }
        drag = nil
        dropTarget = nil
        NSCursor.pop()
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

/// The block being dragged and how far the pointer has moved.
struct BlockDrag: Equatable {
    var blockID: UUID
    var startY: CGFloat
    var currentY: CGFloat
    var offset: CGFloat { currentY - startY }
}

private struct BlockFramesKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

private struct BlockRow: View {
    let block: NoteBlock
    let number: Int?
    let defaults: EditorDefaults
    let focusRequest: FocusRequest?
    let model: NoteEditorModel
    let drag: BlockDrag?
    let dropTarget: DropTarget?
    let onDragChanged: (DragGesture.Value) -> Void
    let onDragEnded: () -> Void
    /// Pointer over the row's SwiftUI parts (grip, gutter) or over its text.
    @State private var isHovered = false
    @State private var isTextHovered = false

    private static let indentWidth: CGFloat = 22
    private static let gutterWidth: CGFloat = 24
    /// Handle (20) + spacing (6) live in the editor's left margin, so block text
    /// stays aligned with the title and nothing shifts when the handle appears.
    private static let handleSpace: CGFloat = 26

    private var isDragged: Bool { drag?.blockID == block.id }

    var body: some View {
        let style = BlockTextStyle(type: block.type, defaults: defaults, isChecked: block.isChecked)
        HStack(alignment: .top, spacing: 6) {
            BlockDragHandle(
                visibility: isHovered || isTextHovered || isDragged ? .full : (model.activeBlockID == block.id ? .hint : .hidden),
                isDragging: isDragged,
                height: style.lineHeight,
                moveUp: { model.moveBlock(block.id, by: -1) },
                moveDown: { model.moveBlock(block.id, by: 1) }
            )
            .gesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .named("SmartNotes.blocks"))
                    .onChanged(onDragChanged)
                    .onEnded { _ in onDragEnded() }
            )

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
        // The dragged block lifts and follows the pointer.
        .background {
            if isDragged {
                RoundedRectangle(cornerRadius: 8)
                    .fill(SNColor.card)
                    .shadow(color: .black.opacity(0.16), radius: 10, y: 5)
                    .padding(.horizontal, -8)
                    .padding(.vertical, -3)
            }
        }
        .scaleEffect(isDragged ? 1.015 : 1)
        .offset(y: isDragged ? (drag?.offset ?? 0) : 0)
        .onHover { isHovered = $0 }
        .overlay(alignment: dropTarget?.placeAfter == true ? .bottom : .top) {
            if dropTarget?.itemID == block.id {
                BlockInsertionIndicator()
                    .padding(.leading, -Self.handleSpace)
                    .offset(y: dropTarget?.placeAfter == true ? 3 : -3)
                    .transition(.opacity)
            }
        }
        .snAnimation(SNMotion.hover, value: dropTarget)
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
            canRedo: { [model] in model.canRedo },
            onSlashToken: { [model] in model.updateSlashToken($0, blockID: id, anchor: $1) },
            onSlashCompleted: { [model] in model.applyCompletedSlashCommand($0, blockID: id, removing: $1) },
            isSlashMenuOpen: { [model] in model.slashMenu?.blockID == id },
            onSlashMove: { [model] in model.moveSlashHighlight(by: $0) },
            onSlashConfirm: { [model] in model.applySlashCommand() },
            onSlashDismiss: { [model] in model.dismissSlashMenu() },
            onHoverChange: { isTextHovered = $0 }
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
                        .contentTransition(.symbolEffect(.replace))
                        .symbolEffect(.bounce, value: block.isChecked)
                }
                .buttonStyle(SNIconButtonStyle(shape: .rounded(5), size: CGSize(width: 22, height: 22)))
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
                .buttonStyle(SNCapsuleButtonStyle())
                .help("Copy this note as Markdown so nothing is lost")
            Button("Retry", action: retry)
                .buttonStyle(SNCapsuleButtonStyle())
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

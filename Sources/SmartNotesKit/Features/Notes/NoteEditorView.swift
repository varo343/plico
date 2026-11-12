import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Title + block body for one note. Minimal chrome; writing comes first.
struct NoteEditorView: View {
    @Bindable var model: NoteEditorModel
    /// Supplies the metadata strip; nil hides it (e.g. in tests).
    var notes: NotesModel?
    var defaults = EditorDefaults()
    @State private var drag: BlockDrag?
    @State private var dropTarget: DropTarget?
    /// The row the dragged block would be tucked into, as nested text.
    @State private var nestTarget: UUID?
    /// A row of nested text being dragged out of its row.
    @State private var rowDrag: NestedRowDrag?
    /// A block dragged beside a one-column note: dropping starts the right column.
    @State private var startsColumn = false
    /// Where pictures being dragged in from outside would go.
    @State private var imageDrop: ImageDropTarget?
    /// Where the rows are. Not state: layout updates it all the time (typing,
    /// resizing, animations), and as state each update re-rendered every row.
    @State private var geometry = EditorGeometry()
    /// Bumped when the blocks area moves during a drag, so the drop zones follow.
    @State private var geometryTick = 0
    @State private var selectionTracker = BlockSelectionTracker()
    /// A picture opened large (click on it).
    @State private var preview: ImagePreview?
    /// A row's attached picture being dragged (out between rows, or onto another row).
    @State private var attachmentDrag: AttachmentDrag?

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
                    let numbers = listNumbers(model.note.blocks)
                    let highlights = Dictionary(model.rangeSegments.map { ($0.blockID, $0.range) }, uniquingKeysWith: { $1 })
                    let columns = BlockEditing.columns(of: model.note)
                    ColumnsLayout(gap: Self.columnGap, reservesSecondColumn: previewsNewColumn) {
                        ForEach(Array(columns.enumerated()), id: \.offset) { _, blocks in
                            let order = blocks.map(\.id)
                            VStack(alignment: .leading, spacing: SNSpacing.xxs) {
                                ForEach(blocks) { block in
                                    row(block, number: numbers[block.id], highlight: highlights[block.id], order: order)
                                }
                            }
                        }
                    }
                    // The line between the columns, as tall as the taller one.
                    .overlay {
                        if columns.count > 1 {
                            Rectangle().fill(SNColor.borderSubtle).frame(width: 1).allowsHitTesting(false)
                        }
                    }
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.blocksSpace)) } action: { frame in
                        geometry.blocksArea = frame
                        if isDragging { geometryTick &+= 1 }
                    }
                    // Over the new-column zone, the rows make room for it.
                    .snAnimation(SNMotion.snappy, value: previewsNewColumn)
                    .snAnimation(SNMotion.snappy, value: model.note.blocks.map(\.id))
                    .snAnimation(SNMotion.snappy, value: model.note.blocks.map(\.column))
                    // Rows slide out of the way as the drop position changes.
                    .snAnimation(SNMotion.snappy, value: dropTarget)
                    // Opening or closing nested text moves the rows below with it.
                    .snAnimation(SNMotion.snappy, value: model.expandedDetails)

                    // Clicking below the blocks continues writing at the end of the
                    // column above. Its height also lets the last line scroll clear
                    // of the New Note button.
                    Color.clear
                        .frame(maxWidth: .infinity, minHeight: 200)
                        .contentShape(Rectangle())
                        .onTapGesture(coordinateSpace: .named(Self.blocksSpace)) { location in
                            model.focusLastBlockEnd(column: column(at: location.x))
                        }
                        .accessibilityHidden(true)
                }
                .background(alignment: .topLeading) {
                    dropZones
                        .snAnimation(SNMotion.snappy, value: drag != nil || imageDrop != nil)
                        .snAnimation(SNMotion.hover, value: startsColumn || imageDrop == .newColumn)
                }
                .overlay(alignment: .topLeading) { dropOverlay }
                .coordinateSpace(name: Self.blocksSpace)
                // Pictures dragged in from Finder or another app (over the text,
                // each block's text view takes the drop itself; see BlockNSTextView).
                .onDrop(of: [.fileURL, .image], delegate: ImageDropDelegate(
                    resolve: imageDropTarget(at:),
                    update: { if $0 != imageDrop { imageDrop = $0 } },
                    perform: dropImages
                ))
                .padding(.horizontal, SNSpacing.xl + SNSpacing.xs)
                .padding(.top, SNSpacing.xxs)
                // Wider with two columns, so each keeps a comfortable line
                // length. Title and blocks widen together, in one animation
                // (also while a drag previews the new column).
                .frame(maxWidth: isWide ? Self.twoColumnWidth : Self.oneColumnWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
                .snAnimation(SNMotion.snappy, value: isWide)
            }
        }
        .overlay {
            if let preview {
                ImageLightbox(preview: preview) { self.preview = nil }
                    .transition(.opacity)
            }
        }
        .snAnimation(SNMotion.snappy, value: preview?.image.id)
        .onAppear {
            selectionTracker.model = model
            model.imagePicker = ImageDrop.pick
        }
        .onChange(of: ObjectIdentifier(model)) {
            selectionTracker.model = model
            model.imagePicker = ImageDrop.pick
        }
        .modifier(SlashMenuPresenter(model: model))
        .sheet(isPresented: Binding(get: { model.linkDraft != nil }, set: { if !$0 { model.cancelLinkEditing() } })) {
            LinkEditorSheet(model: model)
        }
    }

    private func row(_ block: NoteBlock, number: Int?, highlight: Range<Int>?, order: [UUID]) -> some View {
        BlockRow(
            block: block,
            number: number,
            defaults: defaults,
            // Each row gets only what concerns it, so a change elsewhere (the
            // caret moving to another row, a drag) doesn't re-render it.
            focusRequest: model.focusRequest?.blockID == block.id ? model.focusRequest : nil,
            model: model,
            drag: drag?.blockID == block.id ? drag : nil,
            shift: previewShift(of: block.id, order: order),
            tracker: selectionTracker,
            rangeHighlight: highlight,
            isRangeSelecting: model.rangeSelection != nil,
            isNestTarget: nestTarget == block.id,
            nestsPicture: nestTarget == block.id && (attachmentDrag != nil || drag.map { drag in model.note.blocks.first { $0.id == drag.blockID }?.type == .image } == true),
            onDragChanged: { dragChanged(block.id, $0) },
            onDragEnded: { dragEnded(block.id) },
            onRowDragChanged: { rowDragChanged(block.id, row: $0, text: $1, $2) },
            onRowDragEnded: rowDragEnded,
            onImageDragHover: { after in
                let target = after.map { ImageDropTarget.row(DropTarget(itemID: block.id, placeAfter: $0)) }
                if target != imageDrop { imageDrop = target }
            },
            onImageDrop: { data, after in
                Task { model.insertImages(await ImageDrop.images(from: data), relativeTo: block.id, placeAfter: after) }
            },
            onPreviewImage: { preview = ImagePreview(image: $0, caption: block.type == .image ? block.content.plainText : "") },
            onAttachmentDragChanged: { attachmentDragChanged(block.id, $0) },
            onAttachmentDragEnded: attachmentDragEnded,
            isAttachmentDragged: attachmentDrag?.blockID == block.id
        )
        .equatable()
        // New rows (a dropped picture, Return, a row moved to the other column) fade in.
        .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
        // Each row reports its own frame (a preference merged all rows' frames
        // up the tree on every layout pass, typing included).
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.blocksSpace)) } action: { [geometry] frame in
            geometry.liveFrames[block.id] = frame
        }
        .zIndex(drag?.blockID == block.id ? 1 : 0)
        // See-through while hovering a row it would nest into.
        .opacity(drag?.blockID == block.id && (nestTarget != nil || startsColumn) ? 0.7 : 1)
    }

    // MARK: Block drag

    private static let blocksSpace = "SmartNotes.blocks"
    /// Between two columns; wide enough for the right column's drag handles.
    private static let columnGap: CGFloat = 56
    /// The note's width (padding included) with one column, and with two:
    /// about 540 pt per column, close to the one-column line length.
    private static let oneColumnWidth: CGFloat = 760
    private static let twoColumnWidth: CGFloat = 1200

    private var isWide: Bool { model.note.hasColumns || previewsNewColumn }

    private var blockFrames: [UUID: CGRect] { geometry.blockFrames }
    /// Where the blocks are (both columns), in the blocks' coordinate space.
    private var blocksArea: CGRect { geometry.blocksArea }
    private var isDragging: Bool { drag != nil || imageDrop != nil || attachmentDrag != nil || rowDrag != nil }

    /// A block or pictures are over the new-column zone: the rows make room
    /// on the left and the right half shows where the column will be.
    private var previewsNewColumn: Bool { startsColumn || imageDrop == .newColumn }

    /// Where column `index` of a two-column note is (or would be), from the
    /// layout itself, so every highlight lines up with the text.
    private func columnRect(_ index: Int) -> CGRect {
        let width = max(0, (blocksArea.width - Self.columnGap) / 2)
        let x = blocksArea.minX + (index == 0 ? 0 : width + Self.columnGap)
        return CGRect(x: x, y: blocksArea.minY, width: width, height: max(blocksArea.height, 120))
    }

    /// The column under `x` (0 when the note has one): left or right of the middle.
    private func column(at x: CGFloat) -> Int {
        model.note.hasColumns && x >= blocksArea.midX ? 1 : 0
    }

    /// The pointer is over the new-column zone of a one-column note: the right
    /// part of the note (or past it). Once there, it stays until the middle,
    /// so the rows making room don't flicker.
    private func isBesideNote(_ x: CGFloat) -> Bool {
        guard !model.note.hasColumns, blocksArea.width > 0 else { return false }
        let threshold = previewsNewColumn ? blocksArea.midX : blocksArea.minX + blocksArea.width * 0.65
        return x >= threshold
    }

    /// Rows of one column with their frames, top to bottom.
    private func frames(inColumn column: Int) -> [(id: UUID, frame: CGRect)] {
        model.note.blocks.filter { $0.column == column }.compactMap { block in blockFrames[block.id].map { (id: block.id, frame: $0) } }
    }

    private func dragChanged(_ id: UUID, _ value: DragGesture.Value) {
        // ⌥ held (at any point of the drag): drop a copy, the row stays.
        let copies = NSEvent.modifierFlags.contains(.option)
        if drag?.blockID != id {
            geometry.freeze()
            drag = BlockDrag(blockID: id, startY: value.startLocation.y, currentY: value.location.y,
                             startX: value.startLocation.x, currentX: value.location.x, isCopy: copies)
            NSCursor.closedHand.push()
        } else {
            drag?.currentY = value.location.y
            drag?.currentX = value.location.x
            if drag?.isCopy != copies { drag?.isCopy = copies }
        }
        (copies ? NSCursor.dragCopy : NSCursor.closedHand).set()
        let point = value.location
        let besideNote = isBesideNote(point.x)
        if besideNote != startsColumn { startsColumn = besideNote }
        guard !besideNote else {
            nestTarget = nil
            dropTarget = nil
            return
        }
        let ordered = frames(inColumn: column(at: point.x))
        let isPicture = model.note.blocks.first { $0.id == id }?.type == .image
        // Over the middle of a row: tuck it in there (a picture is attached to
        // a row without one). Near a row's edge: reorder. A copy only goes between rows.
        let nest = copies ? nil : DropResolver.nestTarget(pointerY: point.y, frames: ordered, dragged: id).flatMap { target in
            let accepts = isPicture ? BlockEditing.canAttachImage(model.note, to: target)
                : model.note.blocks.first { $0.id == target }?.type != .image
            return accepts ? target : nil
        }
        if nest != nestTarget { nestTarget = nest }
        // Within its own column, a drop next to itself is no move; in the other
        // one (or for a copy), every gap is.
        let target = nest != nil ? nil : ordered.contains(where: { $0.id == id }) && !copies
            ? DropResolver.target(pointerY: point.y, frames: ordered, dragged: id)
            : DropResolver.insertion(pointerY: point.y, frames: ordered)
        let newTarget = target.map { DropTarget(itemID: $0.id, placeAfter: $0.placeAfter) }
        if newTarget != dropTarget { dropTarget = newTarget }
    }

    private func dragEnded(_ id: UUID) {
        if drag?.isCopy == true {
            if startsColumn {
                model.duplicateBlock(id, toColumn: 1)
            } else if let target = dropTarget {
                model.duplicateBlock(id, relativeTo: target.itemID, placeAfter: target.placeAfter)
            }
        } else if startsColumn {
            model.moveBlocks([id], toColumn: 1)
        } else if let nestTarget {
            model.nestBlock(id, into: nestTarget)
        } else if let target = dropTarget {
            model.moveBlock(id, relativeTo: target.itemID, placeAfter: target.placeAfter)
        }
        drag = nil
        geometry.thaw()
        dropTarget = nil
        nestTarget = nil
        startsColumn = false
        NSCursor.pop()
    }

    // MARK: Nested row drag

    private func rowDragChanged(_ id: UUID, row: Range<Int>, text: String, _ value: DragGesture.Value) {
        if rowDrag == nil {
            geometry.freeze()
            NSCursor.closedHand.push()
        }
        rowDrag = NestedRowDrag(blockID: id, row: row, text: text, currentY: value.location.y, currentX: value.location.x)
        let y = value.location.y
        // Back over its own row: put it back, nothing changes.
        if let own = blockFrames[id], own.contains(value.location) {
            nestTarget = nil
            dropTarget = nil
            return
        }
        let ordered = frames(inColumn: column(at: value.location.x))
        // Over the middle of another row: into its nested text. Elsewhere: out, as a row.
        let nest = DropResolver.nestTarget(pointerY: y, frames: ordered, dragged: id)
        if nest != nestTarget { nestTarget = nest }
        let target = nest == nil ? DropResolver.insertion(pointerY: y, frames: ordered) : nil
        let newTarget = target.map { DropTarget(itemID: $0.id, placeAfter: $0.placeAfter) }
        if newTarget != dropTarget { dropTarget = newTarget }
    }

    private func rowDragEnded() {
        if let rowDrag {
            if let nestTarget {
                model.moveNestedRow(rowDrag.row, of: rowDrag.blockID, into: nestTarget)
            } else if let target = dropTarget {
                model.unnestRow(rowDrag.row, of: rowDrag.blockID, relativeTo: target.itemID, placeAfter: target.placeAfter)
            }
            NSCursor.pop()
        }
        rowDrag = nil
        geometry.thaw()
        dropTarget = nil
        nestTarget = nil
    }

    // MARK: A row's picture dragged

    private func attachmentDragChanged(_ id: UUID, _ value: DragGesture.Value) {
        if attachmentDrag == nil {
            geometry.freeze()
            NSCursor.closedHand.push()
        }
        attachmentDrag = AttachmentDrag(blockID: id, location: value.location)
        // Back over its own row: it stays.
        if let own = blockFrames[id], own.contains(value.location) {
            nestTarget = nil
            dropTarget = nil
            return
        }
        let ordered = frames(inColumn: column(at: value.location.x))
        // Over the middle of a row without a picture: it moves there. Elsewhere: out, as an image block.
        let nest = DropResolver.nestTarget(pointerY: value.location.y, frames: ordered, dragged: id)
            .flatMap { BlockEditing.canAttachImage(model.note, to: $0) ? $0 : nil }
        if nest != nestTarget { nestTarget = nest }
        let target = nest == nil ? DropResolver.insertion(pointerY: value.location.y, frames: ordered) : nil
        let newTarget = target.map { DropTarget(itemID: $0.id, placeAfter: $0.placeAfter) }
        if newTarget != dropTarget { dropTarget = newTarget }
    }

    private func attachmentDragEnded() {
        if let attachmentDrag {
            if let nestTarget {
                model.moveAttachedImage(from: attachmentDrag.blockID, to: nestTarget)
            } else if let target = dropTarget {
                model.detachImage(from: attachmentDrag.blockID, relativeTo: target.itemID, placeAfter: target.placeAfter)
            }
            NSCursor.pop()
        }
        attachmentDrag = nil
        geometry.thaw()
        dropTarget = nil
        nestTarget = nil
    }

    // MARK: Dropping pictures

    private func imageDropTarget(at point: CGPoint) -> ImageDropTarget? {
        if isBesideNote(point.x) { return .newColumn }
        return DropResolver.insertion(pointerY: point.y, frames: frames(inColumn: column(at: point.x)))
            .map { .row(DropTarget(itemID: $0.id, placeAfter: $0.placeAfter)) }
    }

    private func dropImages(_ providers: [NSItemProvider], at target: ImageDropTarget) {
        Task {
            let images = await ImageDrop.images(from: await ImageDrop.data(from: providers))
            switch target {
            case .row(let row): model.insertImages(images, relativeTo: row.itemID, placeAfter: row.placeAfter)
            case .newColumn: model.insertImagesInNewColumn(images)
            }
        }
    }

    // MARK: Drop indicators

    /// A line where a nested row, a block moved to the other column, or
    /// dropped pictures would land; a tall one beside the note for a new column.
    /// A nested row also follows the pointer.
    @ViewBuilder private var dropOverlay: some View {
        if let target = imageDrop?.row ?? ((rowDrag != nil || attachmentDrag != nil || drag?.isCopy == true || dragCrossesColumns) ? dropTarget : nil),
           let frame = blockFrames[target.itemID] {
            Capsule()
                .fill(SNColor.focusRing)
                .frame(width: max(frame.width, 40), height: 2)
                .offset(x: frame.minX,
                        y: (target.placeAfter ? frame.maxY + SNSpacing.xxs / 2 : frame.minY - SNSpacing.xxs / 2) - 1)
                .allowsHitTesting(false)
        }
        if let drag, drag.isCopy, let block = model.note.blocks.first(where: { $0.id == drag.blockID }) {
            CopyDragPreview(block: block)
                .offset(x: drag.currentX + 10, y: drag.currentY - 10)
                .allowsHitTesting(false)
        }
        if let attachmentDrag, let image = model.note.blocks.first(where: { $0.id == attachmentDrag.blockID })?.image,
           let picture = NoteImageCache.picture(for: image) {
            Image(nsImage: picture)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 96)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .shadow(color: .black.opacity(0.25), radius: 10, y: 5)
                .opacity(0.9)
                .offset(x: attachmentDrag.location.x + 8, y: attachmentDrag.location.y + 8)
                .allowsHitTesting(false)
        }
        if let rowDrag {
            Text(rowDrag.text)
                .font(.system(size: 12))
                .foregroundStyle(SNColor.textPrimary)
                .lineLimit(1)
                .padding(.horizontal, SNSpacing.xs)
                .padding(.vertical, 4)
                .background(SNColor.card, in: RoundedRectangle(cornerRadius: 6))
                .shadow(color: .black.opacity(0.16), radius: 8, y: 4)
                .frame(maxWidth: 360, alignment: .leading)
                .offset(x: max(rowDrag.currentX - 20, 0), y: rowDrag.currentY - 12)
                .allowsHitTesting(false)
        }
    }

    /// Shown as soon as a block (or pictures from outside) is dragged: where it
    /// can go to sit beside the rest. A one-column note shows a rail at its
    /// right edge that opens into the new column's place when the pointer gets
    /// there; a two-column note outlines the other column, lit up under the pointer.
    @ViewBuilder private var dropZones: some View {
        let _ = geometryTick
        let isDragging = drag != nil || imageDrop != nil || attachmentDrag != nil
        if isDragging, !model.note.hasColumns, blocksArea.width > 0, attachmentDrag == nil {
            if previewsNewColumn {
                let zone = columnRect(1)
                NewColumnIndicator(isActive: true)
                    .frame(width: zone.width, height: zone.height)
                    .offset(x: zone.minX, y: zone.minY)
                    .allowsHitTesting(false)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .trailing)))
            } else {
                NewColumnRail()
                    .frame(width: 22, height: max(blocksArea.height, 120))
                    .offset(x: blocksArea.maxX + SNSpacing.xs, y: blocksArea.minY)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        if model.note.hasColumns, let own = draggedColumn {
            let other = own == 0 ? 1 : 0
            let area = columnRect(other).insetBy(dx: -SNSpacing.s, dy: -SNSpacing.xs)
            ColumnDropHighlight(isActive: column(at: dragPointerX) == other)
                .frame(width: area.width, height: area.height)
                .offset(x: area.minX, y: area.minY)
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }

    /// The column of what is being dragged (a block, or a row's picture).
    private var draggedColumn: Int? {
        guard let id = drag?.blockID ?? attachmentDrag?.blockID else { return nil }
        return model.note.blocks.first { $0.id == id }?.column
    }

    private var dragPointerX: CGFloat { drag?.currentX ?? attachmentDrag?.location.x ?? 0 }

    /// A block dragged to the other column (no rows slide there, so a line shows where it lands).
    private var dragCrossesColumns: Bool {
        guard let drag, let target = dropTarget,
              let from = model.note.blocks.first(where: { $0.id == drag.blockID }),
              let to = model.note.blocks.first(where: { $0.id == target.itemID }) else { return false }
        return from.column != to.column
    }

    /// How far a block slides to make room for the dragged one (live preview),
    /// within one column.
    private func previewShift(of id: UUID, order: [UUID]) -> CGFloat {
        guard let drag, !drag.isCopy, !startsColumn, let height = blockFrames[drag.blockID]?.height else { return 0 }
        let target = dropTarget.map { DropResolver.Target(id: $0.itemID, placeAfter: $0.placeAfter) }
        return DropResolver.previewOffset(of: id, order: order, dragged: drag.blockID, target: target, gap: height + SNSpacing.xxs)
    }

    /// 1-based numbers for consecutive numbered items at the same indent
    /// (a list ends with its column).
    private func listNumbers(_ blocks: [NoteBlock]) -> [UUID: Int] {
        var counters: [Int: Int] = [:]
        var numbers: [UUID: Int] = [:]
        var column = 0
        for block in blocks {
            if block.column != column {
                counters.removeAll()
                column = block.column
            }
            guard block.type == .numberedItem else {
                counters.removeAll()
                continue
            }
            counters = counters.filter { $0.key <= block.indentLevel }
            let next = (counters[block.indentLevel] ?? 0) + 1
            counters[block.indentLevel] = next
            numbers[block.id] = next
        }
        return numbers
    }
}

/// Where a dragged block or note will land.
struct DropTarget: Equatable {
    var itemID: UUID
    var placeAfter: Bool
}

/// Side-by-side columns of equal width, top-aligned. Unlike an HStack, each
/// column is measured once, at its final width: rows are text views whose
/// height takes real work to measure, and typing re-measures them.
private struct ColumnsLayout: Layout {
    var gap: CGFloat
    /// A one-column note keeps the right half free (a block is about to start
    /// the second column there).
    var reservesSecondColumn = false

    private func columnWidth(_ width: CGFloat, count: Int) -> CGFloat {
        let columns = max(count, reservesSecondColumn ? 2 : 1)
        return max(0, (width - gap * CGFloat(columns - 1)) / CGFloat(columns))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 600
        let column = ProposedViewSize(width: columnWidth(width, count: subviews.count), height: nil)
        return CGSize(width: width, height: subviews.map { $0.sizeThatFits(column).height }.max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let width = columnWidth(bounds.width, count: subviews.count)
        for (index, subview) in subviews.enumerated() {
            let x = bounds.minX + CGFloat(index) * (width + gap)
            subview.place(at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading, proposal: ProposedViewSize(width: width, height: nil))
        }
    }
}

/// Where pictures dragged in from outside would go.
enum ImageDropTarget: Equatable {
    case row(DropTarget)
    /// Beside a one-column note: they start the right column.
    case newColumn

    var row: DropTarget? {
        if case .row(let target) = self { target } else { nil }
    }
}

/// Takes pictures dragged over the note (outside the blocks' text).
private struct ImageDropDelegate: DropDelegate {
    let resolve: (CGPoint) -> ImageDropTarget?
    let update: (ImageDropTarget?) -> Void
    let perform: ([NSItemProvider], ImageDropTarget) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.fileURL, .image])
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        update(resolve(info.location))
        return DropProposal(operation: .copy)
    }

    func dropExited(info: DropInfo) {
        update(nil)
    }

    func performDrop(info: DropInfo) -> Bool {
        let target = resolve(info.location)
        update(nil)
        guard let target else { return false }
        perform(info.itemProviders(for: [.fileURL, .image]), target)
        return true
    }
}

/// Beside the note while a block or pictures are dragged: drop there for a
/// new column. Quiet from the start of the drag; lit up when the pointer is over it.
struct NewColumnIndicator: View {
    let isActive: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 10)
            .strokeBorder(SNColor.focusRing.opacity(isActive ? 1 : 0.45), style: StrokeStyle(lineWidth: isActive ? 2 : 1.5, dash: [5, 4]))
            .background(SNColor.focusRing.opacity(isActive ? 0.14 : 0.04), in: RoundedRectangle(cornerRadius: 10))
            .overlay(alignment: .top) {
                VStack(spacing: 4) {
                    Image(systemName: "rectangle.split.2x1")
                        .font(.system(size: 16, weight: .medium))
                        .symbolEffect(.bounce, value: isActive)
                    Text(isActive ? "Release for a new column" : "New column")
                        .font(.system(size: 11, weight: .semibold))
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(SNColor.focusRing.opacity(isActive ? 1 : 0.7))
                .padding(.top, SNSpacing.m)
                .padding(.horizontal, SNSpacing.xs)
            }
            .scaleEffect(isActive ? 1.02 : 1)
            .accessibilityHidden(true)
    }
}

/// At the right edge of a one-column note from the start of a drag: carry
/// the block (or pictures) there to start a second column.
struct NewColumnRail: View {
    var body: some View {
        VStack(spacing: SNSpacing.xs) {
            Image(systemName: "rectangle.split.2x1")
                .font(.system(size: 11, weight: .semibold))
            Capsule()
                .fill(SNColor.focusRing.opacity(0.35))
                .frame(width: 3)
        }
        .foregroundStyle(SNColor.focusRing.opacity(0.75))
        .frame(maxHeight: .infinity, alignment: .top)
        .hoverLabel("Drag here for a second column")
        .accessibilityHidden(true)
    }
}

/// Follows the pointer during a ⌥-drag: what will be copied, with a "+".
struct CopyDragPreview: View {
    let block: NoteBlock

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SNColor.focusRing)
            if let image = block.image, let picture = NoteImageCache.picture(for: image) {
                Image(nsImage: picture).resizable().aspectRatio(contentMode: .fit).frame(height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            if !block.content.isEmpty || block.image == nil {
                Text(block.content.isEmpty ? "Empty row" : block.content.plainText)
                    .font(.system(size: 12))
                    .foregroundStyle(SNColor.textPrimary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, SNSpacing.xs)
        .padding(.vertical, 5)
        .background(SNColor.card, in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(SNColor.focusRing.opacity(0.6), lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
        .frame(maxWidth: 320, alignment: .leading)
        .fixedSize()
    }
}

/// A row's attached picture on its way to another row, or out as an image block.
struct AttachmentDrag: Equatable {
    var blockID: UUID
    var location: CGPoint
}

/// The other column while a block is dragged: it can go there too.
struct ColumnDropHighlight: View {
    let isActive: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 10)
            .strokeBorder(SNColor.focusRing.opacity(isActive ? 0.8 : 0.35), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            .background(SNColor.focusRing.opacity(isActive ? 0.08 : 0.025), in: RoundedRectangle(cornerRadius: 10))
            .snAnimation(SNMotion.hover, value: isActive)
            .accessibilityHidden(true)
    }
}

/// A picture opened large.
struct ImagePreview: Equatable {
    var image: NoteImage
    var caption: String
}

/// Click a picture: it opens over the note, as large as fits (up to 3× its
/// own size). Esc, a click outside or ✕ closes it; it can also open in Preview.
struct ImageLightbox: View {
    let preview: ImagePreview
    let close: () -> Void
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.black.opacity(0.78))
                .contentShape(Rectangle())
                .onTapGesture(perform: close)
            if let picture = NoteImageCache.picture(for: preview.image) {
                VStack(spacing: SNSpacing.s) {
                    Image(nsImage: picture)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: picture.size.width * 3, maxHeight: picture.size.height * 3)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .shadow(color: .black.opacity(0.4), radius: 24, y: 10)
                        .onTapGesture {} // a click on the picture itself keeps it open
                    if !preview.caption.isEmpty {
                        Text(preview.caption)
                            .font(SNFont.secondary)
                            .foregroundStyle(Color.white.opacity(0.85))
                    }
                }
                .padding(.horizontal, 56)
                .padding(.vertical, 48)
                .scaleEffect(appeared || reduceMotion ? 1 : 0.92)
            }
        }
        .overlay(alignment: .topTrailing) {
            HStack(spacing: SNSpacing.xs) {
                Button(action: openInPreview) {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 30, height: 30)
                }
                .hoverLabel("Open in Preview")
                .accessibilityLabel("Open in Preview")
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 30, height: 30)
                }
                .keyboardShortcut(.cancelAction)
                .hoverLabel("Close  esc")
                .accessibilityLabel("Close preview")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.white)
            .background(Color.white.opacity(0.14), in: Capsule())
            .padding(SNSpacing.m)
        }
        .onAppear { withAnimation(reduceMotion ? nil : SNMotion.snappy) { appeared = true } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Image preview")
        .accessibilityAddTraits(.isModal)
    }

    /// Full zoom and markup in the Preview app, from a temporary copy.
    private func openInPreview() {
        let type = (CGImageSourceCreateWithData(preview.image.data as CFData, nil).flatMap(CGImageSourceGetType) as String?)
            .flatMap(UTType.init)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(preview.caption.isEmpty ? "Plico image" : String(preview.caption.prefix(60)))
            .appendingPathExtension(type?.preferredFilenameExtension ?? "png")
        guard (try? preview.image.data.write(to: url)) != nil else { return }
        NSWorkspace.shared.open(url)
    }
}

/// The block being dragged and how far the pointer has moved.
struct BlockDrag: Equatable {
    var blockID: UUID
    var startY: CGFloat
    var currentY: CGFloat
    var startX: CGFloat = 0
    var currentX: CGFloat = 0
    /// ⌥ is held: the drop makes a copy and the row itself stays put.
    var isCopy = false
    var offset: CGFloat { currentY - startY }
    var offsetX: CGFloat { currentX - startX }
}

/// A nested row on its way out of its row; `text` is its first line, shown
/// under the pointer.
struct NestedRowDrag: Equatable {
    var blockID: UUID
    var row: Range<Int>
    var text: String
    var currentY: CGFloat
    var currentX: CGFloat = 0
}

/// Row frames and the blocks area, kept outside SwiftUI state (see `geometry`).
final class EditorGeometry {
    /// Where each row is now.
    var liveFrames: [UUID: CGRect] = [:]
    /// As they were when a drag began: during it, rows are offset (the dragged
    /// one follows the pointer, others slide aside), and drop targets and
    /// highlights must use where the rows really are.
    private var frozenFrames: [UUID: CGRect]?
    var blockFrames: [UUID: CGRect] { frozenFrames ?? liveFrames }
    var blocksArea: CGRect = .zero

    func freeze() { if frozenFrames == nil { frozenFrames = liveFrames } }
    func thaw() { frozenFrames = nil }
}

private struct BlockRow: View, @MainActor Equatable {
    let block: NoteBlock
    let number: Int?
    let defaults: EditorDefaults
    let focusRequest: FocusRequest?
    let model: NoteEditorModel
    let drag: BlockDrag?
    /// Live-preview slide while another block is dragged.
    let shift: CGFloat
    let tracker: BlockSelectionTracker
    let rangeHighlight: Range<Int>?
    let isRangeSelecting: Bool
    /// A block dragged over this row would become its nested text (or, for
    /// a picture, be attached to it).
    let isNestTarget: Bool
    let nestsPicture: Bool
    let onDragChanged: (DragGesture.Value) -> Void
    let onDragEnded: () -> Void
    let onRowDragChanged: (Range<Int>, String, DragGesture.Value) -> Void
    let onRowDragEnded: () -> Void
    /// Pictures dragged over this block's text (see `BlockTextActions`).
    let onImageDragHover: (Bool?) -> Void
    let onImageDrop: ([Data], Bool) -> Void
    /// A click on a picture opens it large.
    let onPreviewImage: (NoteImage) -> Void
    /// The row's attached picture dragged by itself.
    let onAttachmentDragChanged: (DragGesture.Value) -> Void
    let onAttachmentDragEnded: () -> Void
    let isAttachmentDragged: Bool
    /// Pointer over the row's SwiftUI parts (grip, gutter) or over its text.
    @State private var isHovered = false
    @State private var isTextHovered = false

    private static let indentWidth: CGFloat = 22
    private static let gutterWidth: CGFloat = 24
    /// Handle (20) + spacing (6) live in the editor's left margin, so block text
    /// stays aligned with the title and nothing shifts when the handle appears.
    static let handleSpace: CGFloat = 26

    /// Being moved (follows the pointer). A ⌥-drag copy leaves the row in place.
    private var isDragged: Bool { drag?.blockID == block.id && drag?.isCopy != true }
    private var isMenuOpen: Bool { model.menuRowID == block.id }

    private func openMenu(_ event: NSEvent, textView: NSTextView? = nil) {
        let id = block.id
        RowMenu.show(RowMenu.entries(for: id, model: model, textView: textView, openImage: onPreviewImage), for: event) { [model] in
            model.setMenuRow($0 ? id : nil)
        }
    }

    /// Only under the pointer (a right click is always over a hovered row):
    /// an AppKit view per row and picture made the editor slower.
    @ViewBuilder private var rowMenuCatcher: some View {
        if isHovered || isTextHovered || isMenuOpen {
            RowMenuCatcher { openMenu($0) }
        }
    }
    private var isDetailExpanded: Bool { model.isDetailExpanded(block.id) }

    /// Rows re-render only when their own data changes; the callbacks are
    /// left out (they read the editor's current state when called).
    static func == (lhs: BlockRow, rhs: BlockRow) -> Bool {
        lhs.block == rhs.block && lhs.number == rhs.number && lhs.defaults == rhs.defaults
            && lhs.focusRequest == rhs.focusRequest && lhs.model === rhs.model && lhs.drag == rhs.drag
            && lhs.shift == rhs.shift && lhs.tracker === rhs.tracker && lhs.rangeHighlight == rhs.rangeHighlight
            && lhs.isRangeSelecting == rhs.isRangeSelecting && lhs.isNestTarget == rhs.isNestTarget
            && lhs.nestsPicture == rhs.nestsPicture && lhs.isAttachmentDragged == rhs.isAttachmentDragged
    }

    var body: some View {
        let style = BlockTextStyle(type: block.type, defaults: defaults, isChecked: block.isChecked)
        HStack(alignment: .top, spacing: 6) {
            BlockDragHandle(
                visibility: isHovered || isTextHovered || isDragged || isMenuOpen ? .full : (model.activeBlockID == block.id ? .hint : .hidden),
                isDragging: isDragged || isMenuOpen,
                height: style.lineHeight,
                moveUp: { model.moveBlock(block.id, by: -1) },
                moveDown: { model.moveBlock(block.id, by: 1) }
            )
            .gesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .named("SmartNotes.blocks"))
                    .onChanged(onDragChanged)
                    .onEnded { _ in onDragEnded() }
            )
            .overlay { rowMenuCatcher }
            .hoverLabel("Drag to move · ⌥ drag to duplicate · right click for more")

            VStack(alignment: .leading, spacing: SNSpacing.xxs) {
                if block.type == .image {
                    NoteImageView(
                        image: block.image,
                        width: block.imageWidth,
                        isSelected: model.activeBlockID == block.id && model.rangeSelection == nil,
                        open: {
                            model.focus(block.id, offset: .max)
                            if let image = block.image { onPreviewImage(image) }
                        },
                        resize: { model.setImageWidth($0, of: block.id) },
                        delete: { model.deleteImage(of: block.id) },
                        // Dragging the picture itself moves its block, like the grip
                        // (onto a row: attached to it).
                        onMoveChanged: onDragChanged,
                        onMoveEnded: onDragEnded
                    )
                    .overlay { rowMenuCatcher }
                }
                HStack(alignment: .top, spacing: SNSpacing.xxs) {
                    gutter(style: style)
                    BlockTextView(
                        content: block.content,
                        style: style,
                        accessibilityLabel: accessibilityLabel,
                        focusRequest: focusRequest,
                        blockID: block.id,
                        actions: actions,
                        tracker: tracker,
                        rangeHighlight: rangeHighlight,
                        isRangeSelecting: isRangeSelecting
                    )
                    .overlay(alignment: .topLeading) {
                        // A picture's caption is invisible until it has text or the caret.
                        if block.type == .image, block.content.isEmpty, model.activeBlockID == block.id {
                            Text("Add a caption")
                                .font(.system(size: style.baseSize))
                                .foregroundStyle(SNColor.textSecondary.opacity(0.7))
                                .frame(height: style.lineHeight)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                    }
                    if block.type != .image {
                        BlockTagControl(tag: block.tag, blockID: block.id, model: model, isRowHovered: isHovered || isTextHovered,
                                        isRowActive: model.activeBlockID == block.id)
                            .frame(height: style.lineHeight)
                        NestedTextToggle(
                            hasDetail: !block.detail.isEmpty,
                            isExpanded: isDetailExpanded,
                            isRowHovered: isHovered || isTextHovered,
                            toggle: { model.toggleDetail(block.id) }
                        )
                        .frame(height: style.lineHeight)
                    }
                }
                if block.type != .image, let image = block.image {
                    // A picture attached to the row, under its text. Drag it to
                    // another row, or out between rows to make it a block again.
                    NoteImageView(
                        image: image,
                        width: block.imageWidth,
                        isSelected: false,
                        open: { onPreviewImage(image) },
                        resize: { model.setImageWidth($0, of: block.id) },
                        delete: { model.deleteImage(of: block.id) },
                        onMoveChanged: onAttachmentDragChanged,
                        onMoveEnded: onAttachmentDragEnded
                    )
                    .overlay { rowMenuCatcher }
                    .padding(.leading, block.type.hasGutter ? Self.gutterWidth + SNSpacing.xxs : 0)
                    .opacity(isAttachmentDragged ? 0.35 : 1)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topLeading)))
                }
                if isDetailExpanded {
                    NestedTextEditor(
                        block: block, defaults: defaults, focusRequest: focusRequest, model: model,
                        onRowDragChanged: onRowDragChanged, onRowDragEnded: onRowDragEnded,
                        onImageDragHover: onImageDragHover, onImageDrop: onImageDrop
                    )
                        // Lines up with the block's text, past the bullet or checkbox.
                        .padding(.leading, block.type.hasGutter ? Self.gutterWidth + SNSpacing.xxs : 0)
                        // Fades in just under the row (a full-height move would slide it
                        // across the row's own text); the rows below make room.
                        .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: -6)), removal: .opacity))
                }
            }
            .padding(.leading, CGFloat(block.indentLevel) * Self.indentWidth)
        }
        .padding(.leading, -Self.handleSpace)
        .padding(.top, block.type.isHeading ? SNSpacing.xs : 0)
        // The dragged block lifts and follows the pointer.
        .background {
            // Right-clicked: the row its menu acts on, in the menu's own hover grey.
            if isMenuOpen {
                RoundedRectangle(cornerRadius: 8)
                    .fill(SNColor.borderSubtle.opacity(0.6))
                    .padding(.horizontal, -8)
                    .padding(.vertical, -3)
                    .transition(.opacity)
            }
            if isNestTarget {
                RoundedRectangle(cornerRadius: 8)
                    .fill(SNColor.accentSun.opacity(0.6))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(SNColor.focusRing.opacity(0.5), lineWidth: 1.5))
                    .overlay(alignment: .bottomTrailing) {
                        Label(nestsPicture ? "Attach picture" : "Nest inside", systemImage: nestsPicture ? "photo" : "text.alignleft")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(SNColor.focusRing)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(SNColor.card, in: Capsule())
                            .offset(x: -6, y: 9)
                    }
                    .padding(.horizontal, -8)
                    .padding(.vertical, -3)
                    .transition(.opacity)
            }
            if isDragged {
                RoundedRectangle(cornerRadius: 8)
                    .fill(SNColor.card)
                    .shadow(color: .black.opacity(0.16), radius: 10, y: 5)
                    .padding(.horizontal, -8)
                    .padding(.vertical, -3)
            }
        }
        .snAnimation(SNMotion.hover, value: isNestTarget)
        .snAnimation(SNMotion.hover, value: isMenuOpen)
        .scaleEffect(isDragged ? 1.015 : 1)
        .offset(x: isDragged ? (drag?.offsetX ?? 0) : 0, y: isDragged ? (drag?.offset ?? 0) : shift)
        // The dragged block tracks the pointer exactly; only the others animate.
        .transaction { if isDragged { $0.animation = nil } }
        .onHover { isHovered = $0 }
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
            onHoverChange: { isTextHovered = $0 },
            nestedTextMenuTitle: block.type == .image ? nil
                : block.detail.isEmpty ? "Add Nested Text" : (isDetailExpanded ? "Hide Nested Text" : "Show Nested Text"),
            onNestedText: { [model] in
                if block.detail.isEmpty || !model.isDetailExpanded(id) {
                    model.focus(id, offset: .max, isDetail: true)
                } else {
                    model.collapseDetail(id)
                }
            },
            onImageDragHover: onImageDragHover,
            onImageDrop: onImageDrop,
            showRowMenu: { openMenu($0, textView: $1) }
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
        var label = kindLabel
        if let tag = block.tag { label += ", tagged \(tag.label)" }
        if !block.detail.isEmpty { label += ", has nested text" }
        return label
    }

    private var kindLabel: String {
        switch block.type {
        case .heading1: "Heading 1"
        case .heading2: "Heading 2"
        case .heading3: "Heading 3"
        case .bulletItem: "Bulleted item"
        case .numberedItem: "Numbered item \(number ?? 1)"
        case .checklistItem: "Checklist item"
        case .quote: "Quote"
        case .paragraph: "Paragraph"
        case .image: "Image caption"
        }
    }
}

/// Shows or hides a block's nested text. Always visible when there is some
/// (so hidden text is never forgotten); otherwise only on hover, to add it.
private struct NestedTextToggle: View {
    let hasDetail: Bool
    let isExpanded: Bool
    let isRowHovered: Bool
    let toggle: () -> Void

    private var isVisible: Bool { hasDetail || isExpanded || isRowHovered }

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 3) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                MotionIcon(symbol: hasDetail ? "text.alignleft" : "text.badge.plus", size: 11.5)
            }
            .foregroundStyle(hasDetail ? SNColor.textPrimary : SNColor.textSecondary)
            .padding(.horizontal, 4)
        }
        .buttonStyle(SNIconButtonStyle(isActive: isExpanded, shape: .capsule))
        .opacity(isVisible ? 1 : 0)
        .allowsHitTesting(isVisible)
        .snAnimation(SNMotion.hover, value: isRowHovered)
        .snAnimation(SNMotion.snappy, value: isExpanded)
        .hoverLabel(isExpanded ? "Hide nested text  ⌥⌘N" : (hasDetail ? "Show nested text  ⌥⌘N" : "Add nested text  ⌥⌘N"))
        .accessibilityLabel(hasDetail ? "Nested text" : "Add nested text")
        .accessibilityValue(isExpanded ? "Shown" : (hasDetail ? "Hidden" : ""))
    }
}

/// A block's nested text, edited in place under the block. Return adds a line;
/// Backspace in empty nested text closes it; ↑ at the top goes back to the block.
private struct NestedTextEditor: View {
    let block: NoteBlock
    let defaults: EditorDefaults
    let focusRequest: FocusRequest?
    let model: NoteEditorModel
    let onRowDragChanged: (Range<Int>, String, DragGesture.Value) -> Void
    let onRowDragEnded: () -> Void
    let onImageDragHover: (Bool?) -> Void
    let onImageDrop: ([Data], Bool) -> Void
    @State private var grips = NestedRowGrips.State()

    /// One preset smaller than body text, so it reads as secondary.
    private var style: BlockTextStyle {
        let smaller = FontSizePreset.allCases.last { $0.rawValue < defaults.fontSize.rawValue } ?? defaults.fontSize
        return BlockTextStyle(type: .paragraph, defaults: EditorDefaults(fontFamily: defaults.fontFamily, fontSize: smaller), isChecked: false)
    }

    var body: some View {
        HStack(alignment: .top, spacing: SNSpacing.xs) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(SNColor.borderSubtle)
                .frame(width: 3)
                .accessibilityHidden(true)
            BlockTextView(
                content: block.detail,
                style: style,
                accessibilityLabel: "Nested text",
                focusRequest: focusRequest,
                blockID: block.id,
                actions: actions,
                isNestedText: true,
                onRowFrames: { [grips] in grips.rows = $0 }
            )
            .overlay(alignment: .topLeading) {
                if block.detail.isEmpty {
                    Text("Nested text — write or paste here")
                        .font(.system(size: style.baseSize))
                        .foregroundStyle(SNColor.textSecondary.opacity(0.7))
                        .frame(height: style.lineHeight)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            Button { model.removeDetail(block.id) } label: {
                MotionIcon(symbol: "trash", size: 11)
                    .foregroundStyle(SNColor.textSecondary)
            }
            .buttonStyle(SNIconButtonStyle(shape: .capsule, size: CGSize(width: 24, height: 22)))
            .opacity(block.detail.isEmpty ? 0 : 1)
            .allowsHitTesting(!block.detail.isEmpty)
            .hoverLabel("Delete nested text")
            .accessibilityLabel("Delete nested text")
        }
        // Each row gets a grip in the margin, like the blocks above it.
        .overlay(alignment: .topLeading) {
            NestedRowGrips(
                state: grips,
                onChanged: { onRowDragChanged($0, firstLine(of: $0), $1) },
                onEnded: onRowDragEnded,
                moveOut: { [model, id = block.id] in model.unnestRow($0, of: id, relativeTo: id, placeAfter: true) }
            )
        }
        .onHover { [grips] in grips.isHovered = $0 }
        .padding(.vertical, SNSpacing.xxs)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func firstLine(of range: Range<Int>) -> String {
        let text = block.detail.slice(range).plainText
        return String(text.prefix { $0 != "\n" }).trimmingCharacters(in: .whitespaces)
    }

    private var actions: BlockTextActions {
        let id = block.id
        return BlockTextActions(
            onChange: { [model] in model.setDetail($0, ofBlock: id) },
            onSelectionChange: { [model] in model.updateDetailSelection(blockID: id, range: $0) },
            onEnter: { _ in }, // Return inserts a line break in nested text (handled by the text view)
            onBackspaceAtStart: { [model] in model.backspaceAtDetailStart(id) },
            onExitUp: { [model] in
                model.focus(id, offset: .max)
                return true
            },
            onExitDown: { [model] in model.focusNext(after: id, fromDetail: true) },
            onIndent: { _ in false },
            onToggleMark: { [model] in model.toggleMark($0, blockID: id, range: $1, inDetail: true) },
            onEditLink: { [model] in model.beginLinkEditing(blockID: id, range: $0, inDetail: true) },
            onPaste: { [model] in model.pasteIntoDetail($0, blockID: id, range: $1) },
            onMoveBlock: { [model] in model.moveBlock(id, by: $0) },
            onUndo: { [model] in model.undo() },
            onRedo: { [model] in model.redo() },
            canUndo: { [model] in model.canUndo },
            canRedo: { [model] in model.canRedo },
            // Slash commands change blocks; they don't apply inside nested text.
            onSlashToken: { _, _ in },
            onSlashCompleted: { _, _ in },
            isSlashMenuOpen: { false },
            onSlashMove: { _ in },
            onSlashConfirm: {},
            onSlashDismiss: {},
            onHoverChange: { [grips] in grips.isTextHovered = $0 },
            nestedTextMenuTitle: "Hide Nested Text",
            onNestedText: { [model] in model.collapseDetail(id) },
            // Pictures dropped on nested text go in below its block.
            onImageDragHover: onImageDragHover,
            onImageDrop: onImageDrop
        )
    }
}

/// The grips beside nested text's rows, in the margin like the blocks' own.
/// Rows and hover live in `State`, read only here: the text view must not be
/// redrawn while typing whenever a row starts or ends (it would briefly get
/// stale text back and lose the caret).
private struct NestedRowGrips: View {
    @Observable @MainActor final class State {
        var rows: [NestedRowFrame] = []
        var isHovered = false
        var isTextHovered = false
    }

    let state: State
    let onChanged: (Range<Int>, DragGesture.Value) -> Void
    let onEnded: () -> Void
    let moveOut: (Range<Int>) -> Void

    var body: some View {
        ForEach(state.rows, id: \.range) { row in
            NestedRowHandle(
                isVisible: state.isHovered || state.isTextHovered,
                height: row.frame.height,
                onChanged: { onChanged(row.range, $0) },
                onEnded: onEnded,
                moveOut: { moveOut(row.range) }
            )
            .offset(x: -26, y: row.frame.minY)
        }
    }
}

/// Grip beside one row of nested text: drag it out between rows to make it a
/// row again, or onto another row to move it there.
private struct NestedRowHandle: View {
    let isVisible: Bool
    let height: CGFloat
    let onChanged: (DragGesture.Value) -> Void
    let onEnded: () -> Void
    let moveOut: () -> Void
    @State private var isHovered = false

    var body: some View {
        GripDots()
            .fill(isHovered ? SNColor.textPrimary : SNColor.textSecondary)
            .frame(width: 7, height: 11)
            .frame(width: 20, height: max(height, 18))
            .background {
                if isHovered { WobblyRoundedRectShape(radius: 6).fill(SNColor.borderSubtle.opacity(0.7)) }
            }
            .contentShape(Rectangle())
            // Nearly, not fully, transparent: SwiftUI skips hit testing at 0.
            .opacity(isVisible || isHovered ? 1 : 0.001)
            .onHover { inside in
                isHovered = inside
                if inside { NSCursor.openHand.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .named("SmartNotes.blocks"))
                    .onChanged(onChanged)
                    .onEnded { _ in onEnded() }
            )
            .contextMenu { Button("Move Out as a Row", action: moveOut) }
            .snAnimation(SNMotion.hover, value: isVisible)
            .hoverLabel("Drag out to make it a row")
            .accessibilityLabel("Move nested row")
            .accessibilityAction(named: "Move Out as a Row", moveOut)
    }
}

/// A picture: an image block's, or one attached to a row. Outlined while its
/// block has the caret. Click opens it large; the corner handle resizes it
/// (double-click the handle for its own size again); hovering shows a delete
/// button. A row's picture can itself be dragged (`onMoveChanged`).
private struct NoteImageView: View {
    let image: NoteImage?
    /// The chosen width in points; nil is the picture's own size.
    let width: Double?
    let isSelected: Bool
    let open: () -> Void
    let resize: (Double?) -> Void
    let delete: () -> Void
    var onMoveChanged: ((DragGesture.Value) -> Void)?
    var onMoveEnded: (() -> Void)?
    @State private var isHovered = false
    /// The width while the corner is being dragged, and where the drag began.
    @State private var liveWidth: CGFloat?
    @State private var dragStartWidth: CGFloat?
    /// Room in the column.
    @State private var available: CGFloat = 0

    /// Unsized pictures taller than this (a long screenshot) start scaled down.
    private static let maxNaturalHeight: CGFloat = 640
    private static let minWidth: CGFloat = 48

    var body: some View {
        Group {
            if let image, let picture = NoteImageCache.picture(for: image) {
                sized(picture)
            } else {
                Label("This picture can't be shown", systemImage: "photo.badge.exclamationmark")
                    .font(SNFont.secondary)
                    .foregroundStyle(SNColor.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .background(SNColor.borderSubtle.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GeometryReader { proxy in
            Color.clear
                .onAppear { available = proxy.size.width }
                .onChange(of: proxy.size.width) { _, width in available = width }
        })
    }

    /// Width shown: while resizing the live one, else the chosen one, else its
    /// own size (shorter than `maxNaturalHeight`); never wider than the column.
    private func displayWidth(_ size: CGSize) -> CGFloat {
        let natural = size.height > Self.maxNaturalHeight ? size.width * Self.maxNaturalHeight / size.height : size.width
        let wanted = liveWidth ?? width.map { CGFloat($0) } ?? natural
        let limit = available > 0 ? available : wanted
        return max(min(wanted, limit), min(Self.minWidth, limit))
    }

    private func sized(_ picture: NSImage) -> some View {
        let size = picture.size
        let shownWidth = displayWidth(size)
        let shownHeight = size.width > 0 ? shownWidth * size.height / size.width : shownWidth
        let isResizing = liveWidth != nil
        return Image(nsImage: picture)
            .resizable()
            // Cheaper filtering while the size changes under the pointer.
            .interpolation(isResizing ? .medium : .high)
            .frame(width: shownWidth, height: shownHeight)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected || isResizing ? SNColor.focusRing : SNColor.borderSubtle.opacity(0.6),
                                  lineWidth: isSelected || isResizing ? 2 : 1)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: open)
            .gesture(moveGesture)
            .overlay(alignment: .topTrailing) { deleteButton }
            .overlay(alignment: .bottomTrailing) { resizeHandle(currentWidth: shownWidth) }
            .overlay(alignment: .bottomLeading) {
                if let liveWidth {
                    Text("\(Int(liveWidth)) × \(Int(shownHeight))")
                        .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                        .foregroundStyle(SNColor.textPrimary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(SNColor.card.opacity(0.92), in: Capsule())
                        .padding(SNSpacing.xs)
                        .allowsHitTesting(false)
                }
            }
            // Hover covers the picture and its buttons together: tracked on the
            // picture alone, moving onto the delete button "left" the picture,
            // which hid the button just before the click.
            .onHover { isHovered = $0 }
            .snAnimation(SNMotion.hover, value: isHovered)
            // Resizing follows the pointer exactly; a reset (double-click) animates.
            .snAnimation(SNMotion.snappy, value: width)
            .transaction { if isResizing { $0.animation = nil } }
            // Right click: the row menu (a `RowMenuCatcher` over the picture, in the row).
            .accessibilityElement()
            .accessibilityLabel("Image")
            .accessibilityAddTraits([.isImage, .isButton])
            .accessibilityHint("Opens the picture large")
            .accessibilityAction(named: "Delete Image", delete)
            .accessibilityAction(named: "Actual Size") { resize(nil) }
    }

    /// A row's picture follows the pointer to another row or out between rows.
    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named("SmartNotes.blocks"))
            .onChanged { value in onMoveChanged?(value) }
            .onEnded { _ in onMoveEnded?() }
    }

    private var deleteButton: some View {
        Button(action: delete) {
            MotionIcon(symbol: "trash", size: 11)
                .foregroundStyle(SNColor.textPrimary)
        }
        .buttonStyle(SNIconButtonStyle(shape: .capsule, size: CGSize(width: 26, height: 24)))
        .background(SNColor.card.opacity(0.92), in: Capsule())
        .padding(SNSpacing.xs)
        .opacity(isHovered ? 1 : 0)
        .allowsHitTesting(isHovered)
        .onHover { if $0 { isHovered = true } }
        .hoverLabel("Delete image")
        .accessibilityLabel("Delete image")
    }

    /// Drag the corner to resize (the height follows); double-click: own size.
    private func resizeHandle(currentWidth: CGFloat) -> some View {
        let isVisible = isHovered || isSelected || liveWidth != nil
        return RoundedRectangle(cornerRadius: 3)
            .fill(SNColor.card)
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(SNColor.focusRing, lineWidth: 1.5))
            .frame(width: 12, height: 12)
            .frame(width: 26, height: 26) // easier to grab than it looks
            .contentShape(Rectangle())
            .offset(x: 7, y: 7)
            .opacity(isVisible ? 1 : 0)
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let start = dragStartWidth ?? currentWidth
                        if dragStartWidth == nil { dragStartWidth = start }
                        let limit = available > 0 ? available : .greatestFiniteMagnitude
                        liveWidth = min(max(start + value.translation.width, Self.minWidth), limit)
                    }
                    .onEnded { _ in
                        if let liveWidth { resize(Double(liveWidth)) }
                        liveWidth = nil
                        dragStartWidth = nil
                    }
            )
            .simultaneousGesture(TapGesture(count: 2).onEnded { resize(nil) })
            .hoverLabel("Drag to resize · double-click for actual size")
            .accessibilityHidden(true)
    }
}

/// Decoded pictures, by `NoteImage.id`, so typing doesn't decode them again.
@MainActor
enum NoteImageCache {
    private static let cache: NSCache<NSUUID, NSImage> = {
        let cache = NSCache<NSUUID, NSImage>()
        cache.countLimit = 60
        return cache
    }()

    static func picture(for image: NoteImage) -> NSImage? {
        if let cached = cache.object(forKey: image.id as NSUUID) { return cached }
        guard let picture = NSImage(data: image.data) else { return nil }
        cache.setObject(picture, forKey: image.id as NSUUID)
        return picture
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

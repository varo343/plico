import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// In-app note-row drags (declared in the app's Info.plist).
    static let smartNotesNote = UTType(exportedAs: "local.smartnotes.note")
}

/// Middle column: header, search, sort menu, and the pinned/unpinned list.
/// Custom rows (not a system table) so selection, hover and drag match the
/// design language; keyboard: ↑/↓ select, Return edits, Delete trashes.
struct NotesListView: View {
    @Bindable var model: NotesModel
    @FocusState private var searchFocused: Bool
    @FocusState private var listFocused: Bool
    @State private var draggingNoteID: UUID?
    @State private var dropTarget: DropTarget?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if !model.hasAnyNotes {
                EmptyState(symbol: "square.and.pencil", tint: SNColor.accentMint, title: "Write your first note",
                           message: "Click the yellow + button or press ⌘N.")
            } else if model.groups.all.isEmpty {
                EmptyState(symbol: "magnifyingglass", tint: SNColor.borderSubtle, title: "No matches",
                           message: "Nothing in your notes contains “\(model.searchQuery)”. Trash isn't searched.") {
                    Button("Clear Search") { model.searchQuery = "" }
                        .buttonStyle(SNCapsuleButtonStyle())
                }
            } else {
                list
            }
        }
        .background(SNColor.card)
        .onChange(of: model.searchFocusRequest) { searchFocused = true }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: SNSpacing.s) {
            HStack(alignment: .firstTextBaseline) {
                Text("Notes").font(.system(size: 22, weight: .bold)).foregroundStyle(SNColor.textPrimary)
                Text("\(model.activeNotes.count)")
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
                    .foregroundStyle(SNColor.textSecondary)
                    .accessibilityLabel("\(model.activeNotes.count) notes")
                Spacer()
                sortMenu
            }
            searchField
            if model.hasAnyNotes, !model.canReorder {
                Label(model.isSearching ? "Clear search to reorder" : "Sorted by \(model.sortMode.label.lowercased())",
                      systemImage: model.isSearching ? "line.3.horizontal.decrease" : "arrow.up.arrow.down")
                    .font(.system(size: 11))
                    .foregroundStyle(SNColor.textSecondary)
                    .help("Drag to reorder is available in Manual sort")
            }
        }
        .padding(.horizontal, SNSpacing.m)
        .padding(.top, SNSpacing.xs)
        .padding(.bottom, SNSpacing.s)
    }

    private var searchField: some View {
        HStack(spacing: SNSpacing.xs) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(SNColor.textSecondary)
                .accessibilityHidden(true)
            TextField("Search notes", text: $model.searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($searchFocused)
                .onExitCommand { model.searchQuery = ""; searchFocused = false }
                .onKeyPress(.downArrow) { listFocused = true; return .handled }
                .accessibilityLabel("Search notes")
            if !model.searchQuery.isEmpty {
                Button { model.searchQuery = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(SNColor.textSecondary)
                }
                .buttonStyle(SNIconButtonStyle(shape: .capsule, size: CGSize(width: 20, height: 20)))
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(SNColor.canvas, in: RoundedRectangle(cornerRadius: SNRadius.small))
        .overlay(
            RoundedRectangle(cornerRadius: SNRadius.small)
                .stroke(searchFocused ? SNColor.focusRing : SNColor.borderSubtle, lineWidth: searchFocused ? 1.5 : 1)
        )
    }

    private var sortMenu: some View {
        SNDropdown(minWidth: 190, showsChevron: false) {
            [.header("Sort by")] + NoteSortMode.allCases.map { mode in
                .item(SNMenuItem(title: mode.label, icon: mode.symbol, isChecked: model.sortMode == mode) { model.sortMode = mode })
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down").font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(SNColor.textPrimary)
        .hoverLabel("Sort: \(model.sortMode.label)")
        .accessibilityLabel("Sort notes, currently \(model.sortMode.label)")
    }

    // MARK: List

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if !model.groups.pinned.isEmpty {
                        sectionHeader("Pinned", symbol: "pin.fill")
                        rows(model.groups.pinned)
                        sectionHeader("Notes", symbol: nil)
                    }
                    rows(model.groups.others)
                }
                .padding(.horizontal, SNSpacing.xs)
                .padding(.bottom, SNSpacing.l)
            }
            .focusable()
            .focused($listFocused)
            .focusEffectDisabled()
            .onKeyPress(.upArrow) { model.selectAdjacent(-1); return .handled }
            .onKeyPress(.downArrow) { model.selectAdjacent(1); return .handled }
            .onKeyPress(.return) { model.editor?.focusLastBlockEnd(); return .handled }
            .onDeleteCommand { if let id = model.selectedNoteID { model.moveToTrash(id) } }
            .onChange(of: model.selectedNoteID) { _, id in
                if let id { withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id) } }
            }
            .accessibilityLabel("Notes list")
        }
    }

    private func sectionHeader(_ title: String, symbol: String?) -> some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).font(.system(size: 9)) }
            Text(title.uppercased()).tracking(0.6)
        }
        .font(.system(size: 10.5, weight: .semibold))
        .foregroundStyle(SNColor.textSecondary)
        .padding(.horizontal, SNSpacing.xs)
        .padding(.top, SNSpacing.s)
        .padding(.bottom, 2)
        .accessibilityAddTraits(.isHeader)
    }

    private func rows(_ notes: [NoteSummary]) -> some View {
        ForEach(notes) { note in
            NoteListRow(
                note: note,
                isSelected: note.id == model.selectedNoteID,
                isListFocused: listFocused
            ) {
                model.select(note.id)
                listFocused = true
            }
            .id(note.id)
            .contextMenu {
                Button(note.isPinned ? "Unpin" : "Pin") { model.togglePin(note.id) }
                Button("Duplicate") { model.duplicate(note.id) }
                Divider()
                Button("Move to Trash", role: .destructive) { model.moveToTrash(note.id) }
            }
            .overlay(alignment: dropTarget?.placeAfter == true ? .bottom : .top) {
                if dropTarget?.itemID == note.id {
                    BlockInsertionIndicator().padding(.horizontal, SNSpacing.xs).offset(y: dropTarget?.placeAfter == true ? 2 : -2)
                }
            }
            .modifier(NoteRowDrag(
                note: note, enabled: model.canReorder, model: model,
                draggingNoteID: $draggingNoteID, dropTarget: $dropTarget
            ))
        }
    }
}

/// Drag to reorder (Manual sort only). Disabled with an explanation otherwise.
private struct NoteRowDrag: ViewModifier {
    let note: NoteSummary
    let enabled: Bool
    let model: NotesModel
    @Binding var draggingNoteID: UUID?
    @Binding var dropTarget: DropTarget?
    @State private var height: CGFloat = 0

    func body(content: Content) -> some View {
        if enabled {
            content
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
                .onDrag {
                    draggingNoteID = note.id
                    let provider = NSItemProvider()
                    provider.registerDataRepresentation(forTypeIdentifier: UTType.smartNotesNote.identifier, visibility: .ownProcess) { done in
                        done(Data(note.id.uuidString.utf8), nil)
                        return nil
                    }
                    return provider
                }
                .onDrop(of: [.smartNotesNote], delegate: NoteDropDelegate(
                    targetID: note.id, height: height, model: model,
                    draggingNoteID: $draggingNoteID, dropTarget: $dropTarget
                ))
        } else {
            content.help("Choose Manual sort to reorder notes by dragging")
        }
    }
}

private struct NoteDropDelegate: DropDelegate {
    let targetID: UUID
    let height: CGFloat
    let model: NotesModel
    @Binding var draggingNoteID: UUID?
    @Binding var dropTarget: DropTarget?

    func validateDrop(info: DropInfo) -> Bool {
        draggingNoteID != nil && info.hasItemsConforming(to: [.smartNotesNote])
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        let target = DropTarget(itemID: targetID, placeAfter: info.location.y > height / 2)
        if dropTarget != target { dropTarget = target }
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        if dropTarget?.itemID == targetID { dropTarget = nil }
    }

    func performDrop(info: DropInfo) -> Bool {
        defer { draggingNoteID = nil; dropTarget = nil }
        guard let dragged = draggingNoteID else { return false }
        model.moveNote(dragged, relativeTo: targetID, placeAfter: info.location.y > height / 2)
        return true
    }
}

struct NoteListRow: View {
    let note: NoteSummary
    var isSelected = false
    var isListFocused = false
    var today: LocalDay = .today()
    var action: () -> Void = {}
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: SNSpacing.xxs) {
                    Text(note.displayTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(SNColor.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if note.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(SNColor.textSecondary)
                            .accessibilityLabel("Pinned")
                    }
                }
                Text(note.preview.isEmpty ? "No additional text" : note.preview)
                    .font(.system(size: 12.5))
                    .foregroundStyle(SNColor.textSecondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                FlowLayout(spacing: 8) {
                    Text(note.updatedAt, format: .relative(presentation: .named))
                        .font(.system(size: 11))
                        .foregroundStyle(SNColor.textSecondary)
                    PriorityBadge(note.priority, size: .small)
                    if let due = note.dueDate { DateMetadataChip(.due, day: due, today: today, size: .small) }
                    if let planned = note.plannedDate { DateMetadataChip(.planned, day: planned, today: today, size: .small) }
                }
                .padding(.top, 2)
            }
            .padding(.horizontal, SNSpacing.s)
            .padding(.vertical, 10)
            .background { rowBackground }
            .contentShape(RoundedRectangle(cornerRadius: SNRadius.standard))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var rowBackground: some View {
        let shape = RoundedRectangle(cornerRadius: SNRadius.standard)
        if isSelected {
            shape.fill(SNColor.canvas)
                .overlay(shape.stroke(isListFocused ? SNColor.focusRing : SNColor.outline.opacity(0.8), lineWidth: 1.5))
        } else if isHovered {
            shape.fill(SNColor.borderSubtle.opacity(0.35))
        }
    }
}

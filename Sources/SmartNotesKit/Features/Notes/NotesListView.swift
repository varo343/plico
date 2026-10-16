import SwiftUI

/// Middle column: header, search, sort menu, and the pinned/unpinned list.
struct NotesListView: View {
    @Bindable var model: NotesModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if !model.hasAnyNotes {
                EmptyState(symbol: "square.and.pencil", title: "Write your first note",
                           message: "Click the yellow + button or press ⌘N to start.")
            } else if model.groups.all.isEmpty {
                EmptyState(symbol: "magnifyingglass", title: "No results for “\(model.searchQuery)”",
                           message: "Search looks at note titles and text, excluding Trash.") {
                    Button("Clear Search") { model.searchQuery = "" }
                }
            } else {
                list
            }
        }
        .background(SNColor.card)
        .onChange(of: model.searchFocusRequest) { searchFocused = true }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: SNSpacing.xs) {
            HStack {
                Text("Notes").font(SNFont.section).foregroundStyle(SNColor.textPrimary)
                Spacer()
                sortMenu
            }
            HStack(spacing: SNSpacing.xs) {
                Image(systemName: "magnifyingglass").foregroundStyle(SNColor.textSecondary).accessibilityHidden(true)
                TextField("Search", text: $model.searchQuery)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .onExitCommand { model.searchQuery = ""; searchFocused = false }
                    .accessibilityLabel("Search notes")
                if !model.searchQuery.isEmpty {
                    Button { model.searchQuery = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(SNColor.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, SNSpacing.xs)
            .padding(.vertical, 5)
            .background(SNColor.canvas, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(SNColor.borderSubtle))

            if model.hasAnyNotes, !model.canReorder {
                Text(model.isSearching ? "Clear search to reorder notes" : "Sorted by \(model.sortMode.label) · choose Manual to drag")
                    .font(.system(size: 11))
                    .foregroundStyle(SNColor.textSecondary)
            }
        }
        .padding(.horizontal, SNSpacing.m)
        .padding(.top, SNSpacing.s)
        .padding(.bottom, SNSpacing.xs)
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort By", selection: $model.sortMode) {
                ForEach(NoteSortMode.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Sort notes (currently \(model.sortMode.label))")
        .accessibilityLabel("Sort notes, currently \(model.sortMode.label)")
    }

    private var list: some View {
        List(selection: Binding(get: { model.selectedNoteID }, set: { model.select($0) })) {
            if !model.groups.pinned.isEmpty {
                Section("Pinned") {
                    rows(model.groups.pinned, pinned: true)
                }
            }
            Section(model.groups.pinned.isEmpty ? "" : "Notes") {
                rows(model.groups.others, pinned: false)
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .contentMargins(.bottom, 88, for: .scrollContent) // FAB clearance in narrow layouts
        .contextMenu(forSelectionType: UUID.self) { ids in
            if let id = ids.first {
                Button(model.isPinned(id) ? "Unpin" : "Pin") { model.togglePin(id) }
                Button("Duplicate") { model.duplicate(id) }
                Divider()
                Button("Move to Trash", role: .destructive) { model.moveToTrash(id) }
            }
        }
        .onDeleteCommand {
            if let id = model.selectedNoteID { model.moveToTrash(id) }
        }
    }

    private func rows(_ notes: [NoteSummary], pinned: Bool) -> some View {
        ForEach(notes) { note in
            NoteListRow(note: note)
                .tag(note.id)
                .help(model.canReorder ? "" : "Switch to Manual sort to reorder by dragging")
        }
        .onMove(perform: model.canReorder ? { model.move(inPinnedGroup: pinned, from: $0, to: $1) } : nil)
    }
}

struct NoteListRow: View {
    let note: NoteSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: SNSpacing.xxs) {
                if note.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(SNColor.textSecondary)
                        .accessibilityLabel("Pinned")
                }
                Text(note.displayTitle)
                    .font(SNFont.rowTitle)
                    .foregroundStyle(SNColor.textPrimary)
                    .lineLimit(1)
            }
            Text(note.preview.isEmpty ? "No additional text" : note.preview)
                .font(SNFont.secondary)
                .foregroundStyle(SNColor.textSecondary)
                .lineLimit(2)
            // Chips wrap rather than truncate: "Overdue" must stay readable,
            // never conveyed by color alone.
            FlowLayout {
                updatedLabel
                chips
            }
            .lineLimit(1)
        }
        .padding(.vertical, SNSpacing.xxs)
        .accessibilityElement(children: .combine)
    }

    private var updatedLabel: some View {
        Text(note.updatedAt, format: .relative(presentation: .named))
            .font(.system(size: 11))
            .foregroundStyle(SNColor.textSecondary)
    }

    @ViewBuilder
    private var chips: some View {
        PriorityBadge(note.priority)
        if let planned = note.plannedDate { DateMetadataChip(.planned, day: planned) }
        if let due = note.dueDate { DateMetadataChip(.due, day: due) }
    }
}

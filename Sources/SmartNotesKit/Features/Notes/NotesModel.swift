import Foundation
import Observation

/// State and commands for the Notes and Trash destinations: list, search,
/// sorting, selection, and the active editor session.
@MainActor
@Observable
public final class NotesModel {
    public private(set) var groups = NoteSorter.Groups(pinned: [], others: [])
    public private(set) var trashed: [NoteSummary] = []
    public private(set) var selectedNoteID: UUID?
    public private(set) var editor: NoteEditorModel?
    /// Most recently trashed note, offered for Undo.
    public private(set) var recentlyTrashed: NoteSummary?
    /// User-facing message for a failed list operation.
    public var errorMessage: String?
    /// Incremented to ask the list to focus its search field (⌘F).
    public private(set) var searchFocusRequest = 0

    public var searchQuery = "" {
        didSet { if searchQuery != oldValue { reload() } }
    }

    public var sortMode: NoteSortMode {
        didSet {
            guard sortMode != oldValue else { return }
            var settings = settingsStore.load()
            settings.sortMode = sortMode
            settingsStore.save(settings)
            regroup()
        }
    }

    /// Drag reordering only makes sense in Manual sort over the full list.
    public var canReorder: Bool { sortMode == .manual && !isSearching }
    public var isSearching: Bool { !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty }
    public var hasAnyNotes: Bool { !activeNotes.isEmpty }

    @ObservationIgnored private let repository: NoteRepository
    @ObservationIgnored private let settingsStore: SettingsStore
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let autosaveDelay: Duration
    /// All active (non-trashed) notes, unfiltered by search. Drives Today.
    public private(set) var activeNotes: [NoteSummary] = []
    /// Search hits (or all notes when not searching).
    @ObservationIgnored private var visibleNotes: [NoteSummary] = []

    public init(
        repository: NoteRepository,
        settings: SettingsStore,
        autosaveDelay: Duration = .milliseconds(400),
        now: @escaping () -> Date = Date.init
    ) {
        self.repository = repository
        self.settingsStore = settings
        self.autosaveDelay = autosaveDelay
        self.now = now
        self.sortMode = settings.load().sortMode
    }

    /// Initial load: opens the most recently edited note.
    public func load() {
        reload()
        if let recent = activeNotes.max(by: { $0.updatedAt < $1.updatedAt }) {
            select(recent.id)
        }
    }

    public func reload() {
        perform("load your notes") {
            activeNotes = try repository.summaries(in: .active)
            visibleNotes = isSearching ? try repository.search(searchQuery, in: .active) : activeNotes
            trashed = try repository.summaries(in: .trashed).sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
        }
        regroup()
    }

    // MARK: Selection

    public func select(_ id: UUID?) {
        guard id != selectedNoteID || (id != nil && editor == nil) else { return }
        flush()
        selectedNoteID = id
        editor = nil
        guard let id else { return }
        perform("open the note") {
            guard let note = try repository.note(id: id), !note.isTrashed else {
                selectedNoteID = nil
                return
            }
            editor = NoteEditorModel(
                note: note, repository: repository, autosaveDelay: autosaveDelay, now: now,
                onSaved: { [weak self] _ in self?.reload() }
            )
        }
    }

    /// Keyboard navigation in the list (↑ / ↓).
    public func selectAdjacent(_ offset: Int) {
        let ordered = groups.all
        guard !ordered.isEmpty else { return }
        guard let current = selectedNoteID, let index = ordered.firstIndex(where: { $0.id == current }) else {
            select(ordered[offset > 0 ? 0 : ordered.count - 1].id)
            return
        }
        let target = min(max(index + offset, 0), ordered.count - 1)
        if target != index { select(ordered[target].id) }
    }

    public func requestSearchFocus() {
        searchFocusRequest += 1
    }

    // MARK: Commands

    /// ⌘N / FAB: creates an empty note at the top and focuses its first block.
    public func createNote() {
        flush()
        searchQuery = ""
        let timestamp = now()
        let note = Note(
            createdAt: timestamp,
            manualRank: ManualOrdering.rankForNewNote(existing: activeNotes),
            blocks: [NoteBlock(rank: Rank.initial)]
        )
        perform("create a note") { try repository.save(note) }
        reload()
        select(note.id)
        editor?.focusFirstBlock()
    }

    /// Saves a prepared note (e.g. created from an email) and opens it.
    public func addNote(_ note: Note) {
        flush()
        searchQuery = ""
        perform("create the note") { try repository.save(note) }
        reload()
        select(note.id)
        editor?.focusLastBlockEnd()
    }

    public func duplicate(_ id: UUID) {
        flush()
        perform("duplicate the note") {
            guard let original = try repository.note(id: id) else { return }
            let copy = original.duplicated(now: now(), manualRank: ManualOrdering.rankAfter(id, existing: activeNotes))
            try repository.save(copy)
            reload()
            select(copy.id)
        }
    }

    public func togglePin(_ id: UUID) {
        perform("change the pin") {
            try repository.updateMetadata(id: id) { $0.isPinned.toggle() }
        }
        reload()
    }

    public func isPinned(_ id: UUID) -> Bool {
        summary(for: id)?.isPinned ?? false
    }

    /// Current list metadata for a note (pin, priority, dates).
    public func summary(for id: UUID) -> NoteSummary? {
        activeNotes.first { $0.id == id }
    }

    // MARK: Priority and dates (explicit user choices only)

    public func setPriority(_ priority: Priority, for id: UUID) {
        perform("change the priority") { try repository.updateMetadata(id: id) { $0.priority = priority } }
        reload()
    }

    /// When the user intends to work on the note. `nil` clears it.
    public func setPlannedDate(_ day: LocalDay?, for id: UUID) {
        perform("change the planned date") { try repository.updateMetadata(id: id) { $0.plannedDate = day } }
        reload()
    }

    /// The note's deadline. `nil` clears it.
    public func setDueDate(_ day: LocalDay?, for id: UUID) {
        perform("change the due date") { try repository.updateMetadata(id: id) { $0.dueDate = day } }
        reload()
    }

    public func moveToTrash(_ id: UUID) {
        if id == selectedNoteID { flush() }
        let ordered = groups.all
        let summary = activeNotes.first { $0.id == id }
        perform("move the note to Trash") { try repository.moveToTrash(id: id, at: now()) }
        reload()
        recentlyTrashed = summary
        if id == selectedNoteID {
            // Select the neighbour so keyboard users keep their place.
            let position = ordered.firstIndex { $0.id == id } ?? 0
            let remaining = groups.all
            select(remaining.isEmpty ? nil : remaining[min(position, remaining.count - 1)].id)
        }
    }

    public func undoTrash() {
        guard let note = recentlyTrashed else { return }
        recentlyTrashed = nil
        restore(note.id)
        select(note.id)
    }

    public func dismissUndo() {
        recentlyTrashed = nil
    }

    public func restore(_ id: UUID) {
        perform("restore the note") { try repository.restore(id: id) }
        if recentlyTrashed?.id == id { recentlyTrashed = nil }
        reload()
    }

    public func deletePermanently(_ id: UUID) {
        perform("delete the note") { try repository.deletePermanently(id: id) }
        if recentlyTrashed?.id == id { recentlyTrashed = nil }
        reload()
    }

    public func emptyTrash() {
        perform("empty the Trash") { try repository.emptyTrash() }
        recentlyTrashed = nil
        reload()
    }

    /// Manual-sort drag within the pinned or unpinned group.
    public func move(inPinnedGroup pinned: Bool, from source: IndexSet, to destination: Int) {
        guard canReorder else { return }
        let group = pinned ? groups.pinned : groups.others
        let updates = ManualOrdering.move(in: group, from: source, to: destination)
        perform("reorder notes") {
            for (id, rank) in updates {
                try repository.updateMetadata(id: id) { $0.manualRank = rank }
            }
        }
        reload()
    }

    /// Drag and drop in Manual sort: places `id` before or after `targetID`.
    /// Notes only move within their own group (pinned or not).
    public func moveNote(_ id: UUID, relativeTo targetID: UUID, placeAfter: Bool) {
        guard canReorder, id != targetID else { return }
        for (pinned, group) in [(true, groups.pinned), (false, groups.others)] {
            guard let from = group.firstIndex(where: { $0.id == id }),
                  let target = group.firstIndex(where: { $0.id == targetID }) else { continue }
            move(inPinnedGroup: pinned, from: [from], to: placeAfter ? target + 1 : target)
            return
        }
    }

    /// Writes pending editor changes immediately (focus loss, quit, ⌘S, switching notes).
    public func flush() {
        editor?.flush()
    }

    // MARK: Private

    private func regroup() {
        groups = NoteSorter.grouped(visibleNotes, by: sortMode)
    }

    private func perform(_ action: String, _ body: () throws -> Void) {
        do {
            try body()
        } catch {
            errorMessage = "Couldn't \(action). \(error.localizedDescription)"
            Log.persistence.error("Failed to \(action, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}

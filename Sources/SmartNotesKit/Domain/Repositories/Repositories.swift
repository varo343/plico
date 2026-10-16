import Foundation

// Repository protocols isolate views and domain commands from SwiftData.
// They are main-actor bound: the store is local, writes are small, and the
// editor needs synchronous, ordered saves. Heavy work (sync, export) can move to
// a background ModelActor behind these same protocols later.

@MainActor
public protocol NoteRepository: AnyObject {
    /// Summaries for the list, most recently updated first. Sorting rules are
    /// applied by the domain layer, not here.
    func summaries(in scope: NoteScope) throws -> [NoteSummary]

    /// Notes whose title or body contains `query` (case/diacritic-insensitive).
    func search(_ query: String, in scope: NoteScope) throws -> [NoteSummary]

    func note(id: UUID) throws -> Note?

    /// Inserts or replaces the whole note and its blocks. Used for creation,
    /// duplication and import. Callers set `updatedAt`.
    func save(_ note: Note) throws

    /// Editor autosave path: writes only title, blocks and `updatedAt`, so a
    /// pending autosave can never overwrite metadata changed elsewhere.
    func updateContent(id: UUID, title: String, blocks: [NoteBlock], updatedAt: Date) throws

    /// Metadata path (pin, rank, priority, dates). Does not touch content or `updatedAt`.
    func updateMetadata(id: UUID, _ change: (inout NoteMetadata) -> Void) throws

    func moveToTrash(id: UUID, at date: Date) throws

    /// Clears `deletedAt`; all other state (pin, rank, metadata) is untouched.
    func restore(id: UUID) throws

    func deletePermanently(id: UUID) throws

    /// Permanently deletes every trashed note. Returns how many were removed.
    @discardableResult
    func emptyTrash() throws -> Int

    /// Every note including Trash, with blocks (for export).
    func allNotes() throws -> [Note]

    /// Permanently deletes every note, including Trash.
    func deleteAll() throws
}

/// Note fields that can change independently of the note's content.
public struct NoteMetadata: Hashable, Sendable {
    public var isPinned: Bool
    public var priority: Priority
    public var plannedDate: LocalDay?
    public var dueDate: LocalDay?
    public var manualRank: String

    public init(isPinned: Bool, priority: Priority, plannedDate: LocalDay?, dueDate: LocalDay?, manualRank: String) {
        self.isPinned = isPinned
        self.priority = priority
        self.plannedDate = plannedDate
        self.dueDate = dueDate
        self.manualRank = manualRank
    }
}

public struct UpsertSummary: Equatable, Sendable {
    public var inserted: Int
    public var updated: Int

    public init(inserted: Int, updated: Int) {
        self.inserted = inserted
        self.updated = updated
    }
}

@MainActor
public protocol ExternalItemRepository: AnyObject {
    /// Newest first.
    func items(provider: ExternalProvider, accountId: String, includeDismissed: Bool) throws -> [ExternalItem]

    func item(id: UUID) throws -> ExternalItem?

    /// Deduplicates on `(provider, accountId, externalId)`. Updates remote
    /// fields of existing items but never their local dismissed/seen state.
    @discardableResult
    func upsert(_ drafts: [ExternalItemDraft], syncedAt: Date) throws -> UpsertSummary

    /// Removes items the provider reports as deleted.
    func remove(keys: [ExternalItemKey]) throws

    func setDismissed(id: UUID, _ dismissed: Bool) throws
    func setSeen(id: UUID, _ seen: Bool) throws

    /// Clears cached metadata for an account (e.g. on Disconnect). Never touches notes.
    @discardableResult
    func removeAll(provider: ExternalProvider, accountId: String) throws -> Int
}

@MainActor
public protocol IntegrationStateRepository: AnyObject {
    func state(provider: ExternalProvider, accountId: String) throws -> IntegrationState?
    func save(_ state: IntegrationState) throws
    func remove(provider: ExternalProvider, accountId: String) throws
}

/// Small, non-relational preferences.
public protocol SettingsStore: Sendable {
    func load() -> AppSettings
    func save(_ settings: AppSettings)
}

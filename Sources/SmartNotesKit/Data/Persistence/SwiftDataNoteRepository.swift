import Foundation
import SwiftData

@MainActor
public final class SwiftDataNoteRepository: NoteRepository {
    // Holding the container keeps the store alive for as long as the repository;
    // a ModelContext alone does not retain it.
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    public init(container: ModelContainer) {
        self.container = container
    }

    public func summaries(in scope: NoteScope) throws -> [NoteSummary] {
        try context.fetch(descriptor(scope: scope, query: nil)).map(Self.summary)
    }

    public func search(_ query: String, in scope: NoteScope) throws -> [NoteSummary] {
        let folded = NoteText.fold(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !folded.isEmpty else { return try summaries(in: scope) }
        return try context.fetch(descriptor(scope: scope, query: folded)).map(Self.summary)
    }

    public func note(id: UUID) throws -> Note? {
        guard let record = try record(id: id) else { return nil }
        return try Self.note(from: record)
    }

    public func save(_ note: Note) throws {
        let record: NoteRecord
        if let existing = try self.record(id: note.id) {
            record = existing
        } else {
            record = NoteRecord(
                id: note.id, title: "", createdAt: note.createdAt, updatedAt: note.updatedAt,
                isPinned: false, deletedAt: nil, priorityRaw: Priority.none.rawValue,
                plannedDay: nil, dueDay: nil, manualRank: note.manualRank,
                sourceExternalItemId: nil, searchText: "", previewText: "", displayTitle: ""
            )
            context.insert(record)
        }

        record.createdAt = note.createdAt
        record.updatedAt = note.updatedAt
        record.isPinned = note.isPinned
        record.deletedAt = note.deletedAt
        record.priorityRaw = note.priority.rawValue
        record.plannedDay = note.plannedDate?.isoString
        record.dueDay = note.dueDate?.isoString
        record.manualRank = note.manualRank
        record.sourceExternalItemId = note.sourceExternalItemId
        try applyContent(to: record, title: note.title, blocks: note.blocks)
        try context.save()
    }

    public func updateContent(id: UUID, title: String, blocks: [NoteBlock], updatedAt: Date) throws {
        guard let record = try record(id: id) else { throw PersistenceError.noteNotFound(id) }
        record.updatedAt = updatedAt
        try applyContent(to: record, title: title, blocks: blocks)
        try context.save()
    }

    public func updateMetadata(id: UUID, _ change: (inout NoteMetadata) -> Void) throws {
        guard let record = try record(id: id) else { throw PersistenceError.noteNotFound(id) }
        var metadata = NoteMetadata(
            isPinned: record.isPinned,
            priority: Priority(rawValue: record.priorityRaw) ?? .none,
            plannedDate: record.plannedDay.flatMap(LocalDay.init(isoString:)),
            dueDate: record.dueDay.flatMap(LocalDay.init(isoString:)),
            manualRank: record.manualRank
        )
        change(&metadata)
        record.isPinned = metadata.isPinned
        record.priorityRaw = metadata.priority.rawValue
        record.plannedDay = metadata.plannedDate?.isoString
        record.dueDay = metadata.dueDate?.isoString
        record.manualRank = metadata.manualRank
        try context.save()
    }

    public func moveToTrash(id: UUID, at date: Date) throws {
        guard let record = try record(id: id) else { return }
        record.deletedAt = date
        try context.save()
    }

    public func restore(id: UUID) throws {
        guard let record = try record(id: id) else { return }
        record.deletedAt = nil
        try context.save()
    }

    public func deletePermanently(id: UUID) throws {
        guard let record = try record(id: id) else { return }
        context.delete(record)
        try context.save()
    }

    @discardableResult
    public func emptyTrash() throws -> Int {
        let trashed = try context.fetch(descriptor(scope: .trashed, query: nil))
        trashed.forEach(context.delete)
        try context.save()
        return trashed.count
    }

    // MARK: - Private

    private func record(id: UUID) throws -> NoteRecord? {
        var descriptor = FetchDescriptor<NoteRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func descriptor(scope: NoteScope, query: String?) -> FetchDescriptor<NoteRecord> {
        let predicate: Predicate<NoteRecord>
        switch (scope, query) {
        case (.active, nil):
            predicate = #Predicate { $0.deletedAt == nil }
        case (.trashed, nil):
            predicate = #Predicate { $0.deletedAt != nil }
        case (.active, let q?):
            predicate = #Predicate { $0.deletedAt == nil && $0.searchText.contains(q) }
        case (.trashed, let q?):
            predicate = #Predicate { $0.deletedAt != nil && $0.searchText.contains(q) }
        }
        return FetchDescriptor(predicate: predicate, sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
    }

    /// Writes title and blocks plus everything derived from them.
    private func applyContent(to record: NoteRecord, title: String, blocks: [NoteBlock]) throws {
        let sorted = blocks.sorted { $0.rank < $1.rank }
        let body = sorted.map(\.content.plainText).joined(separator: "\n")
        record.title = title
        record.searchText = NoteText.searchText(title: title, blocks: sorted)
        record.previewText = NoteText.preview(title: title, body: body)
        record.displayTitle = NoteText.displayTitle(title: title, body: body)
        try syncBlocks(of: record, to: sorted)
    }

    /// Diffs block records against the domain blocks by ID: updates in place,
    /// inserts new ones, deletes removed ones.
    private func syncBlocks(of record: NoteRecord, to blocks: [NoteBlock]) throws {
        var existing = Dictionary(record.blocks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for block in blocks {
            let data = try block.content.encodedData()
            if let blockRecord = existing.removeValue(forKey: block.id) {
                if blockRecord.typeRaw != block.type.rawValue { blockRecord.typeRaw = block.type.rawValue }
                if blockRecord.rank != block.rank { blockRecord.rank = block.rank }
                if blockRecord.contentData != data { blockRecord.contentData = data }
                if blockRecord.isChecked != block.isChecked { blockRecord.isChecked = block.isChecked }
                if blockRecord.indentLevel != block.indentLevel { blockRecord.indentLevel = block.indentLevel }
            } else {
                let blockRecord = BlockRecord(
                    id: block.id, typeRaw: block.type.rawValue, rank: block.rank, contentData: data,
                    isChecked: block.isChecked, indentLevel: block.indentLevel
                )
                context.insert(blockRecord)
                blockRecord.note = record
            }
        }
        for orphan in existing.values {
            context.delete(orphan)
        }
    }

    private static func summary(_ r: NoteRecord) -> NoteSummary {
        NoteSummary(
            id: r.id, title: r.title, displayTitle: r.displayTitle, preview: r.previewText, createdAt: r.createdAt,
            updatedAt: r.updatedAt, isPinned: r.isPinned, deletedAt: r.deletedAt,
            priority: Priority(rawValue: r.priorityRaw) ?? .none,
            plannedDate: r.plannedDay.flatMap(LocalDay.init(isoString:)),
            dueDate: r.dueDay.flatMap(LocalDay.init(isoString:)),
            manualRank: r.manualRank
        )
    }

    private static func note(from r: NoteRecord) throws -> Note {
        let blocks = try r.blocks.map { b in
            let content: RichText
            do {
                content = try RichText.decode(from: b.contentData)
            } catch {
                // Surface instead of silently dropping the block's text.
                throw PersistenceError.undecodableBlock(id: b.id, underlying: error)
            }
            return NoteBlock(
                id: b.id,
                // Unknown type raw values degrade to paragraph; the text is kept.
                type: BlockType(rawValue: b.typeRaw) ?? .paragraph,
                rank: b.rank, content: content, isChecked: b.isChecked, indentLevel: b.indentLevel
            )
        }
        return Note(
            id: r.id, title: r.title, createdAt: r.createdAt, updatedAt: r.updatedAt,
            isPinned: r.isPinned, deletedAt: r.deletedAt,
            priority: Priority(rawValue: r.priorityRaw) ?? .none,
            plannedDate: r.plannedDay.flatMap(LocalDay.init(isoString:)),
            dueDate: r.dueDay.flatMap(LocalDay.init(isoString:)),
            manualRank: r.manualRank, sourceExternalItemId: r.sourceExternalItemId,
            blocks: blocks
        )
    }
}

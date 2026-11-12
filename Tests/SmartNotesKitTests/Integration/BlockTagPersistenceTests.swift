import Foundation
import SwiftData
import Testing
@testable import SmartNotesKit

@MainActor
@Suite struct BlockTagPersistenceTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    @Test func tagsRoundTripThroughTheStore() throws {
        let repo = try AppDependencies.inMemory().notes
        let note = Note(createdAt: now, manualRank: Rank.initial, blocks: [
            NoteBlock(type: .checklistItem, rank: "a", content: RichText(plain: "Call supplier"), tag: .priority(.high)),
            NoteBlock(type: .bulletItem, rank: "b", content: RichText(plain: "Moodboard"), tag: .custom("Design")),
            NoteBlock(type: .bulletItem, rank: "c", content: RichText(plain: "Untagged")),
        ])
        try repo.save(note)
        #expect(try repo.note(id: note.id) == note)

        var edited = note
        edited.blocks[0].tag = nil
        edited.blocks[2].tag = .priority(.low)
        try repo.updateContent(id: note.id, title: "", blocks: edited.blocks, updatedAt: now)
        #expect(try repo.note(id: note.id)?.blocks.map(\.tag) == [nil, .custom("Design"), .priority(.low)])
    }

    @Test func searchFindsTagNames() throws {
        let repo = try AppDependencies.inMemory().notes
        let note = Note(createdAt: now, manualRank: Rank.initial, blocks: [
            NoteBlock(rank: "a", content: RichText(plain: "Call supplier"), tag: .custom("Fornitori")),
        ])
        try repo.save(note)
        #expect(try repo.search("fornitori", in: .active).map(\.id) == [note.id])
    }

    /// A store written by the previous version (schema V1, no tags) opens with
    /// every note intact and blocks untagged; tags can then be saved.
    @Test func migratesAVersion1StoreKeepingNotes() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("SmartNotes.store")
        let noteID = UUID(), blockID = UUID()

        do {
            let schema = Schema(versionedSchema: SmartNotesSchemaV1.self)
            let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url))
            let context = ModelContext(container)
            let record = SmartNotesSchemaV1.NoteRecord(
                id: noteID, title: "Groceries", createdAt: now, updatedAt: now, isPinned: true, deletedAt: nil,
                priorityRaw: "high", plannedDay: nil, dueDay: nil, manualRank: Rank.initial, sourceExternalItemId: nil,
                searchText: "groceries", previewText: "Milk", displayTitle: "Groceries"
            )
            context.insert(record)
            let block = SmartNotesSchemaV1.BlockRecord(
                id: blockID, typeRaw: BlockType.checklistItem.rawValue, rank: "a",
                contentData: try RichText(plain: "Milk").encodedData(), isChecked: true, indentLevel: 0
            )
            context.insert(block)
            block.note = record
            try context.save()
        }

        let repo = SwiftDataNoteRepository(container: try PersistenceController.makeContainer(.onDisk(url)))
        var note = try #require(try repo.note(id: noteID))
        #expect(note.title == "Groceries")
        #expect(note.isPinned && note.priority == .high)
        #expect(note.blocks.map(\.id) == [blockID])
        #expect(note.blocks[0].content.plainText == "Milk" && note.blocks[0].isChecked)
        #expect(note.blocks[0].tag == nil)

        note.blocks[0].tag = .priority(.medium)
        try repo.save(note)
        #expect(try repo.note(id: noteID)?.blocks[0].tag == .priority(.medium))
    }
}

import Foundation
import SwiftData
import Testing
@testable import SmartNotesKit

@MainActor
@Suite struct NoteRepositoryTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func makeRepository() throws -> NoteRepository {
        try AppDependencies.inMemory().notes
    }

    @Test func saveAndFetchRoundTripsEverything() throws {
        let repo = try makeRepository()
        for note in SampleData.notes(now: now) {
            try repo.save(note)
            let fetched = try #require(try repo.note(id: note.id))
            #expect(fetched == note)
        }
    }

    @Test func updateEditsReordersAndRemovesBlocks() throws {
        let repo = try makeRepository()
        var note = SampleData.notes(now: now)[0]
        try repo.save(note)

        let removed = note.blocks.removeLast()
        note.blocks[0].content = RichText(runs: [TextRun("Edited", marks: [.bold])])
        // Move the last remaining block to the top, preserving its formatting.
        let moved = note.blocks[note.blocks.count - 1]
        note.blocks[note.blocks.count - 1].rank = try Rank.between(nil, note.blocks[0].rank)
        note.blocks.append(NoteBlock(type: .checklistItem, rank: try Rank.between(note.blocks.last!.rank, nil),
                                     content: RichText(plain: "New"), isChecked: true))
        try repo.save(note)

        let fetched = try #require(try repo.note(id: note.id))
        #expect(fetched == note)
        #expect(fetched.blocks.first?.id == moved.id)
        #expect(fetched.blocks.first?.content == moved.content)
        #expect(!fetched.blocks.contains { $0.id == removed.id })
        #expect(fetched.blocks.last?.isChecked == true)
    }

    @Test func summariesExposeListMetadataAndPreview() throws {
        let repo = try makeRepository()
        let notes = SampleData.notes(now: now)
        for note in notes { try repo.save(note) }
        let summaries = try repo.summaries(in: .active)
        #expect(summaries.count == notes.count)
        #expect(summaries.map(\.updatedAt) == summaries.map(\.updatedAt).sorted(by: >))
        let ideas = try #require(summaries.first { $0.id == notes[3].id })
        #expect(ideas.title.isEmpty)
        #expect(ideas.displayTitle == "Café ideas for the team offsite")
        #expect(ideas.preview == "Venues Somewhere quiet with good light.")
        #expect(ideas.dueDate == notes[3].dueDate)
        #expect(ideas.priority == .low)
    }

    @Test func trashRestoreAndEmptyTrash() throws {
        let repo = try makeRepository()
        let notes = SampleData.notes(now: now)
        for note in notes { try repo.save(note) }

        try repo.moveToTrash(id: notes[0].id, at: now)
        try repo.moveToTrash(id: notes[1].id, at: now)
        #expect(try repo.summaries(in: .active).count == notes.count - 2)
        #expect(Set(try repo.summaries(in: .trashed).map(\.id)) == [notes[0].id, notes[1].id])

        try repo.restore(id: notes[0].id)
        let restored = try #require(try repo.note(id: notes[0].id))
        #expect(restored == notes[0]) // prior state, including pin and rank

        #expect(try repo.emptyTrash() == 1)
        #expect(try repo.note(id: notes[1].id) == nil)
        #expect(try repo.summaries(in: .trashed).isEmpty)
    }

    @Test func searchMatchesTitleAndBodyAndExcludesTrash() throws {
        let repo = try makeRepository()
        let notes = SampleData.notes(now: now)
        for note in notes { try repo.save(note) }

        #expect(try repo.search("quarterly", in: .active).map(\.id) == [notes[2].id])   // title
        #expect(try repo.search("COFFEE beans", in: .active).map(\.id) == [notes[1].id]) // body, case
        #expect(try repo.search("cafe", in: .active).map(\.id) == [notes[3].id])         // diacritics
        #expect(try repo.search("no such text", in: .active).isEmpty)
        #expect(try repo.search("   ", in: .active).count == notes.count)

        try repo.moveToTrash(id: notes[2].id, at: now)
        #expect(try repo.search("quarterly", in: .active).isEmpty)
        #expect(try repo.search("quarterly", in: .trashed).map(\.id) == [notes[2].id])
    }

    @Test func deletePermanentlyRemovesBlocksToo() throws {
        let deps = try AppDependencies.inMemory()
        let note = SampleData.notes(now: now)[0]
        try deps.notes.save(note)
        try deps.notes.deletePermanently(id: note.id)
        #expect(try deps.notes.note(id: note.id) == nil)
        let orphanBlocks = try deps.modelContainer.mainContext.fetchCount(FetchDescriptor<BlockRecord>())
        #expect(orphanBlocks == 0)
    }

    @Test func largeNoteWith500BlocksRoundTrips() throws {
        let repo = try makeRepository()
        let ranks = Rank.evenlySpaced(500)
        let note = Note(createdAt: now, manualRank: "i", blocks: ranks.enumerated().map { i, rank in
            NoteBlock(type: i.isMultiple(of: 3) ? .checklistItem : .paragraph, rank: rank,
                      content: RichText(runs: [TextRun("Block \(i) "), TextRun("bold", marks: [.bold])]),
                      isChecked: i.isMultiple(of: 2))
        })
        let clock = ContinuousClock()
        let elapsed = try clock.measure {
            try repo.save(note)
            #expect(try repo.note(id: note.id) == note)
        }
        // Coarse guard against pathological regressions, not a benchmark.
        #expect(elapsed < .seconds(5))
    }

    /// Acceptance criterion: create note, quit, reopen → content retained.
    @Test func persistsAcrossContainerRelaunchOnDisk() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SmartNotesTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Test.store")
        let notes = SampleData.notes(now: now)

        do {
            let container = try PersistenceController.makeContainer(.onDisk(url))
            let deps = AppDependencies(modelContainer: container, settings: UserDefaultsSettingsStore(), isInMemory: false)
            for note in notes { try deps.notes.save(note) }
            try deps.notes.moveToTrash(id: notes[4].id, at: now)
        }

        let reopened = try PersistenceController.makeContainer(.onDisk(url))
        let repo = SwiftDataNoteRepository(container: reopened)
        for note in notes.dropLast() {
            #expect(try repo.note(id: note.id) == note)
        }
        #expect(try repo.note(id: notes[4].id)?.deletedAt == now)
        #expect(try repo.summaries(in: .active).count == notes.count - 1)
    }
}

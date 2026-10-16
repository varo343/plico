import Foundation
import Testing
@testable import SmartNotesKit

@Suite struct NoteExportTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    @Test func jsonRoundTripsEveryNoteLosslessly() throws {
        var notes = SampleData.notes(now: now)
        notes[4].deletedAt = now // trashed notes are part of a full backup
        let data = try NoteExport.json(notes, exportedAt: now)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let document = try decoder.decode(NoteExport.Document.self, from: data)
        #expect(document.version == 1 && document.notes.count == notes.count)
        for (exported, note) in zip(document.notes, notes) {
            #expect(exported.id == note.id && exported.title == note.title)
            #expect(exported.blocks.map(\.content) == note.blocks.map(\.content))
            #expect(exported.blocks.map(\.type) == note.blocks.map(\.type))
            #expect(exported.dueDate == note.dueDate && exported.priority == note.priority)
        }
        #expect(document.notes[4].deletedAt != nil)
    }

    @Test func markdownCoversBlocksMarksAndMetadata() throws {
        let note = Note(
            title: "Plan", createdAt: now, isPinned: true, priority: .high,
            dueDate: LocalDay(isoString: "2026-10-20"), manualRank: "i",
            blocks: zip([
                NoteBlock(type: .heading1, rank: "", content: RichText(plain: "Goals")),
                NoteBlock(type: .paragraph, rank: "", content: RichText(runs: [
                    TextRun("Ship "), TextRun("v1", marks: [.bold]), TextRun(" with "),
                    TextRun("docs", link: URL(string: "https://example.com")), TextRun(" and a_b"),
                ])),
                NoteBlock(type: .checklistItem, rank: "", content: RichText(plain: "Done"), isChecked: true),
                NoteBlock(type: .checklistItem, rank: "", content: RichText(plain: "Todo"), indentLevel: 1),
                NoteBlock(type: .numberedItem, rank: "", content: RichText(plain: "One")),
                NoteBlock(type: .numberedItem, rank: "", content: RichText(plain: "Two")),
                NoteBlock(type: .quote, rank: "", content: RichText(runs: [TextRun("Wise", marks: [.italic])])),
            ], Rank.evenlySpaced(7)).map { block, rank in var b = block; b.rank = rank; return b }
        )
        let markdown = NoteExport.markdown(note)
        #expect(markdown == """
        ---
        priority: high
        due: 2026-10-20
        pinned: true
        ---

        # Plan

        ## Goals

        Ship **v1** with [docs](https://example.com) and a\\_b

        - [x] Done
          - [ ] Todo
        1. One
        2. Two

        > *Wise*

        """)
    }

    @Test func fileNamesAreSafeAndUnique() {
        var used = Set<String>()
        let a = Note(title: "Q3: plan / budget", createdAt: now, manualRank: "i")
        let b = Note(title: "q3: plan / budget", createdAt: now, manualRank: "i")
        let c = Note(title: "", createdAt: now, manualRank: "i")
        #expect(NoteExport.fileName(for: a, used: &used) == "Q3- plan - budget.md")
        #expect(NoteExport.fileName(for: b, used: &used) == "q3- plan - budget 2.md")
        #expect(NoteExport.fileName(for: c, used: &used) == "Untitled.md")
    }
}

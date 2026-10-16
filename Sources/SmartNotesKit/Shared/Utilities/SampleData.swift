import Foundation

/// Representative fixtures for tests, previews and `--sample-data` demo runs.
/// Covers every block type, every inline mark, presets, checklist state,
/// priorities, pinning, and planned/due dates relative to `now`.
public enum SampleData {
    public static func notes(now: Date, calendar: Calendar = .current) -> [Note] {
        let today = LocalDay(date: now, calendar: calendar)
        let ranks = Rank.evenlySpaced(5)

        func blocks(_ specs: [(BlockType, RichText, Bool, Int)]) -> [NoteBlock] {
            let blockRanks = Rank.evenlySpaced(specs.count)
            return zip(specs, blockRanks).map { spec, rank in
                NoteBlock(type: spec.0, rank: rank, content: spec.1, isChecked: spec.2, indentLevel: spec.3)
            }
        }

        let welcome = Note(
            title: "Welcome to Smart Notes",
            createdAt: now.addingTimeInterval(-86_400 * 3),
            updatedAt: now.addingTimeInterval(-3_600),
            isPinned: true,
            manualRank: ranks[0],
            blocks: blocks([
                (.heading1, RichText(plain: "Writing comes first"), false, 0),
                (.paragraph, RichText(runs: [
                    TextRun("Notes support "),
                    TextRun("bold", marks: [.bold]),
                    TextRun(", "),
                    TextRun("italic", marks: [.italic]),
                    TextRun(", "),
                    TextRun("underline", marks: [.underline]),
                    TextRun(", "),
                    TextRun("strikethrough", marks: [.strikethrough]),
                    TextRun(" and "),
                    TextRun("links", link: URL(string: "https://www.apple.com/macos/")),
                    TextRun("."),
                ]), false, 0),
                (.heading2, RichText(plain: "Blocks"), false, 0),
                (.bulletItem, RichText(plain: "Each paragraph is a block"), false, 0),
                (.bulletItem, RichText(plain: "Blocks can be reordered\nwithout losing formatting"), false, 1),
                (.quote, RichText(runs: [TextRun("Small, calm, reliable.", marks: [.italic], fontFamily: .serif)]), false, 0),
            ])
        )

        let groceries = Note(
            title: "Weekend errands",
            createdAt: now.addingTimeInterval(-86_400 * 2),
            updatedAt: now.addingTimeInterval(-7_200),
            priority: .medium,
            plannedDate: today,
            manualRank: ranks[1],
            blocks: blocks([
                (.checklistItem, RichText(plain: "Pick up dry cleaning"), true, 0),
                (.checklistItem, RichText(plain: "Buy coffee beans"), false, 0),
                (.checklistItem, RichText(plain: "Call the plumber"), false, 0),
            ])
        )

        let report = Note(
            title: "Quarterly report",
            createdAt: now.addingTimeInterval(-86_400 * 10),
            updatedAt: now.addingTimeInterval(-86_400),
            priority: .high,
            plannedDate: today.adding(days: -3),
            dueDate: today.adding(days: -1),
            manualRank: ranks[2],
            blocks: blocks([
                (.heading2, RichText(plain: "Outline"), false, 0),
                (.numberedItem, RichText(plain: "Summary of results"), false, 0),
                (.numberedItem, RichText(plain: "Risks"), false, 0),
                (.paragraph, RichText(runs: [
                    TextRun("Run "),
                    TextRun("make report", marks: [.code], fontFamily: .monospaced),
                    TextRun(" before sending."),
                ]), false, 0),
            ])
        )

        let ideas = Note(
            title: "",
            createdAt: now.addingTimeInterval(-86_400 * 20),
            updatedAt: now.addingTimeInterval(-86_400 * 5),
            priority: .low,
            dueDate: today,
            manualRank: ranks[3],
            blocks: blocks([
                (.paragraph, RichText(runs: [TextRun("Café ideas for the team offsite", fontSize: .large)]), false, 0),
                (.heading3, RichText(plain: "Venues"), false, 0),
                (.paragraph, RichText(plain: "Somewhere quiet with good light."), false, 0),
            ])
        )

        let later = Note(
            title: "Reading list",
            createdAt: now.addingTimeInterval(-86_400 * 30),
            updatedAt: now.addingTimeInterval(-86_400 * 12),
            plannedDate: today.adding(days: 7),
            manualRank: ranks[4],
            blocks: blocks([
                (.bulletItem, RichText(plain: "The Design of Everyday Things"), false, 0),
                (.bulletItem, RichText(plain: "Thinking in Systems"), false, 0),
            ])
        )

        return [welcome, groceries, report, ideas, later]
    }
}

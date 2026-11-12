import Foundation
import Testing
@testable import SmartNotesKit

@Suite struct BlockTagTests {
    private func note(_ blocks: [NoteBlock]) -> Note {
        Note(createdAt: .now, manualRank: "i", blocks: blocks)
    }

    @Test func namesAreTrimmedLimitedAndMapPriorities() {
        #expect(BlockTag.named("  Design ") == .custom("Design"))
        #expect(BlockTag.named("HIGH") == .priority(.high))
        #expect(BlockTag.named("none") == .custom("none"))
        #expect(BlockTag.named("   ") == nil)
        #expect(BlockTag.named(String(repeating: "x", count: 40))?.label.count == BlockTag.maxCustomLength)
    }

    @Test func storageValueRoundTripsAndRejectsUnknown() throws {
        for tag in [BlockTag.priority(.high), .priority(.medium), .priority(.low), .custom("Client: ACME")] {
            #expect(BlockTag(storageValue: tag.storageValue) == tag)
            #expect(try JSONDecoder().decode(BlockTag.self, from: JSONEncoder().encode(tag)) == tag)
        }
        #expect(BlockTag(storageValue: "priority:none") == nil)
        #expect(BlockTag(storageValue: "priority:urgent") == nil)
        #expect(BlockTag(storageValue: "custom:") == nil)
        #expect(BlockTag(storageValue: "color:red") == nil)
    }

    @Test func pastedParagraphsWithoutTagStillDecode() throws {
        let legacy = #"{"type":"bulletItem","content":{"version":1,"runs":[{"text":"x","marks":[]}]},"indentLevel":0,"isChecked":false}"#
        let paragraph = try JSONDecoder().decode(PastedParagraph.self, from: Data(legacy.utf8))
        #expect(paragraph.tag == nil && paragraph.content.plainText == "x")
    }

    @Test func slashTagListsEveryTagCommandAndIsNeverAppliedDirectly() {
        #expect(SlashCommand.matches("tag").map(\.name) == ["high", "medium", "low", "custom", "untag"])
        #expect(SlashCommand.exact("tag") == nil)
        #expect(SlashTrigger.completedCommand(in: "/tag ", caret: 5) == nil)
        #expect(SlashCommand.exact("high")?.action == .tag(.priority(.high)))
        #expect(SlashTrigger.completedCommand(in: "Call /low ", caret: 10)?.0.action == .tag(.priority(.low)))
    }

    @Test func slashTagRemovesTypedTextAndKeepsKind() throws {
        let block = NoteBlock(type: .checklistItem, rank: "i", content: RichText(plain: "Call supplier /high"))
        let result = try BlockEditing.applySlashCommand(note([block]), blockID: block.id, removing: 14..<19, action: .tag(.priority(.high)))
        #expect(result.note.blocks[0].tag == .priority(.high))
        #expect(result.note.blocks[0].type == .checklistItem)
        #expect(result.note.blocks[0].content.plainText == "Call supplier ")

        let removed = try BlockEditing.applySlashCommand(result.note, blockID: block.id, removing: 14..<14, action: .removeTag)
        #expect(removed.note.blocks[0].tag == nil)
    }

    @Test func splitKeepsTheTagOnTheOriginalLineOnly() throws {
        let block = NoteBlock(type: .bulletItem, rank: "i", content: RichText(plain: "Milk"), tag: .priority(.high))
        let atEnd = try BlockEditing.split(note([block]), blockID: block.id, atUTF16Offset: 4)
        #expect(atEnd.note.blocks.map(\.tag) == [.priority(.high), nil])
        let atStart = try BlockEditing.split(note([block]), blockID: block.id, atUTF16Offset: 0)
        #expect(atStart.note.blocks.map(\.tag) == [nil, .priority(.high)])
    }

    @Test func mergeKeepsAnExistingTag() throws {
        let a = NoteBlock(rank: "a", content: RichText(plain: "A"))
        let b = NoteBlock(rank: "b", content: RichText(plain: "B"), tag: .custom("Design"))
        let merged = try #require(try BlockEditing.mergeWithPrevious(note([a, b]), blockID: b.id))
        #expect(merged.note.blocks.map(\.tag) == [.custom("Design")])
    }

    @Test func copyPasteAndDuplicateCarryTags() throws {
        let a = NoteBlock(type: .bulletItem, rank: "a", content: RichText(plain: "One"), tag: .priority(.low))
        let b = NoteBlock(type: .bulletItem, rank: "b", content: RichText(plain: "Two"), tag: .custom("Design"))
        let source = note([a, b])
        let copied = BlockEditing.copiedParagraphs(source, selection: BlockRangeSelection(
            anchor: BlockPosition(blockID: a.id, offset: 0), focus: BlockPosition(blockID: b.id, offset: 3)))
        #expect(copied.map(\.tag) == [.priority(.low), .custom("Design")])

        let target = NoteBlock(rank: "i")
        let pasted = try #require(try BlockEditing.paste(note([target]), blockID: target.id, range: 0..<0, paragraphs: copied))
        #expect(pasted.note.blocks.map(\.tag) == [.priority(.low), .custom("Design")])

        #expect(source.duplicated(now: .now, manualRank: "j").blocks.map(\.tag) == [.priority(.low), .custom("Design")])
    }

    @Test func exportsIncludeTags() throws {
        let blocks = [
            NoteBlock(type: .checklistItem, rank: "a", content: RichText(plain: "Call supplier"), tag: .priority(.high)),
            NoteBlock(type: .bulletItem, rank: "b", content: RichText(plain: "Moodboard"), tag: .custom("Client review")),
            NoteBlock(type: .bulletItem, rank: "c", content: RichText(plain: "Plain")),
        ]
        let markdown = NoteExport.markdown(Note(title: "T", createdAt: .now, manualRank: "i", blocks: blocks))
        #expect(markdown.contains("- [ ] Call supplier #high\n"))
        #expect(markdown.contains("- Moodboard #client-review\n"))
        #expect(markdown.contains("- Plain\n"))

        let json = String(decoding: try NoteExport.json([note(blocks)], exportedAt: .now), as: UTF8.self)
        #expect(json.contains(#""tag" : "priority:high""#))
        #expect(json.contains(#""tag" : "custom:Client review""#))
    }
}

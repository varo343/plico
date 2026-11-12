import AppKit
import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import SmartNotesKit

@MainActor
@Suite struct ColumnsAndImagesPersistenceTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    @Test func columnsAndPicturesRoundTripThroughTheStore() throws {
        let repo = try AppDependencies.inMemory().notes
        let image = TestImages.image()
        let note = Note(createdAt: now, manualRank: Rank.initial, blocks: [
            NoteBlock(rank: "a", content: RichText(plain: "Left")),
            NoteBlock(type: .image, rank: "b", content: RichText(plain: "Sketch"), column: 1, image: image, imageWidth: 240),
            NoteBlock(rank: "c", content: RichText(plain: "Right"), column: 1),
        ])
        try repo.save(note)
        let loaded = try #require(try repo.note(id: note.id))
        #expect(loaded == note)
        #expect(loaded.blocks[1].image?.data == image.data)
        #expect(loaded.blocks[1].imageWidth == 240)

        // A caption edit leaves the picture alone; deleting the block removes it.
        var edited = loaded
        edited.blocks[1].content = RichText(plain: "Sketch v2")
        try repo.updateContent(id: note.id, title: "", blocks: edited.blocks, updatedAt: now)
        #expect(try repo.note(id: note.id)?.blocks[1].image?.data == image.data)
        edited.blocks.remove(at: 1)
        try repo.updateContent(id: note.id, title: "", blocks: edited.blocks, updatedAt: now)
        #expect(try repo.note(id: note.id)?.blocks.map(\.type) == [.paragraph, .paragraph])
    }

    @Test func duplicatesKeepColumnsAndPictures() {
        let note = Note(createdAt: now, manualRank: "i", blocks: [
            NoteBlock(rank: "a", content: RichText(plain: "L")),
            NoteBlock(type: .image, rank: "b", column: 1, image: TestImages.image()),
        ])
        let copy = note.duplicated(now: now, manualRank: "j")
        #expect(copy.blocks.map(\.column) == [0, 1])
        #expect(copy.blocks[1].image == note.blocks[1].image)
    }

    /// A store written by the previous version (schema V4, pictures without a
    /// chosen size) opens with its pictures at their own size.
    @Test func migratesAVersion4StoreKeepingPictures() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("SmartNotes.store")
        let noteID = UUID(), blockID = UUID(), imageID = UUID()
        let data = TestImages.data(width: 40, height: 30)

        do {
            let schema = Schema(versionedSchema: SmartNotesSchemaV4.self)
            let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url))
            let context = ModelContext(container)
            let record = SmartNotesSchemaV4.NoteRecord(
                id: noteID, title: "Board", createdAt: now, updatedAt: now, isPinned: false, deletedAt: nil,
                priorityRaw: "none", plannedDay: nil, dueDay: nil, manualRank: Rank.initial, sourceExternalItemId: nil,
                searchText: "board", previewText: "", displayTitle: "Board"
            )
            context.insert(record)
            let block = SmartNotesSchemaV4.BlockRecord(
                id: blockID, typeRaw: BlockType.image.rawValue, rank: "a", contentData: try RichText.empty.encodedData(),
                isChecked: false, indentLevel: 0, columnIndex: 1, imageData: data, imageID: imageID
            )
            context.insert(block)
            block.note = record
            try context.save()
        }

        let repo = SwiftDataNoteRepository(container: try PersistenceController.makeContainer(.onDisk(url)))
        var note = try #require(try repo.note(id: noteID))
        #expect(note.blocks[0].image?.data == data && note.blocks[0].image?.id == imageID)
        #expect(note.blocks[0].imageWidth == nil)
        note.blocks[0].imageWidth = 200
        try repo.save(note)
        #expect(try repo.note(id: noteID)?.blocks[0].imageWidth == 200)
    }

    /// A store written by the previous version (schema V3, nested text but no
    /// columns or pictures) opens with everything in the left column.
    @Test func migratesAVersion3StoreKeepingNotes() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("SmartNotes.store")
        let noteID = UUID(), blockID = UUID()

        do {
            let schema = Schema(versionedSchema: SmartNotesSchemaV3.self)
            let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url))
            let context = ModelContext(container)
            let record = SmartNotesSchemaV3.NoteRecord(
                id: noteID, title: "Translations", createdAt: now, updatedAt: now, isPinned: false, deletedAt: nil,
                priorityRaw: "none", plannedDay: nil, dueDay: nil, manualRank: Rank.initial, sourceExternalItemId: nil,
                searchText: "translations", previewText: "", displayTitle: "Translations"
            )
            context.insert(record)
            let block = SmartNotesSchemaV3.BlockRecord(
                id: blockID, typeRaw: BlockType.paragraph.rawValue, rank: "a",
                contentData: try RichText(plain: "AlternativeEmailAddress").encodedData(), isChecked: false, indentLevel: 0,
                tagRaw: nil, detailData: try RichText(plain: "Draft").encodedData()
            )
            context.insert(block)
            block.note = record
            try context.save()
        }

        let repo = SwiftDataNoteRepository(container: try PersistenceController.makeContainer(.onDisk(url)))
        var note = try #require(try repo.note(id: noteID))
        #expect(note.blocks.map(\.id) == [blockID])
        #expect(note.blocks[0].detail.plainText == "Draft")
        #expect(note.blocks[0].column == 0 && note.blocks[0].image == nil)

        note.blocks.append(NoteBlock(type: .image, rank: "b", column: 1, image: TestImages.image()))
        try repo.save(note)
        #expect(try repo.note(id: noteID)?.blocks.map(\.column) == [0, 1])
    }
}

@MainActor
@Suite struct ColumnsAndImagesModelTests {
    private func makeEditor(_ blocks: [NoteBlock]) throws -> NoteEditorModel {
        let deps = try AppDependencies.inMemory()
        let note = Note(createdAt: .now, manualRank: "i", blocks: blocks)
        try deps.notes.save(note)
        return NoteEditorModel(note: note, repository: deps.notes, autosaveDelay: .seconds(60))
    }

    @Test func moveToRightColumnIsOneUndoStepAndKeepsTheCaret() throws {
        let editor = try makeEditor([NoteBlock(rank: "a", content: RichText(plain: "One")), NoteBlock(rank: "b", content: RichText(plain: "Two"))])
        let id = editor.note.blocks[0].id
        editor.updateSelection(blockID: id, range: 2..<2)
        editor.moveSelection(toColumn: 1)
        #expect(editor.note.blocks.map(\.column) == [0, 1])
        #expect(editor.focusRequest?.blockID == id && editor.focusRequest?.offset == 2)
        editor.undo()
        #expect(!editor.note.hasColumns)
    }

    @Test func aSelectionMovesTogether() throws {
        let editor = try makeEditor((0..<3).map { NoteBlock(rank: "\($0)", content: RichText(plain: "Row \($0)")) })
        let ids = editor.note.blocks.map(\.id)
        editor.setRangeSelection(anchor: BlockPosition(blockID: ids[1], offset: 0), focus: BlockPosition(blockID: ids[2], offset: 2))
        editor.moveSelection(toColumn: 1)
        #expect(editor.note.blocks.map(\.column) == [0, 1, 1])
        #expect(editor.rangeSelection == nil)
    }

    @Test func picturesAreInsertedAndDeletedAsOneUndoStepEach() throws {
        let editor = try makeEditor([NoteBlock(rank: "a", content: RichText(plain: "Board"))])
        let id = editor.note.blocks[0].id
        #expect(editor.insertImages([TestImages.image()], relativeTo: id, placeAfter: true))
        let picture = try #require(editor.note.blocks.last)
        #expect(picture.type == .image)
        #expect(editor.focusRequest?.blockID == picture.id)

        editor.deleteBlock(picture.id)
        #expect(editor.note.blocks.map(\.type) == [.paragraph])
        editor.undo()
        #expect(editor.note.blocks.map(\.type) == [.paragraph, .image])
        editor.flush()
    }

    @Test func resizingIsOneUndoStep() throws {
        let editor = try makeEditor([NoteBlock(type: .image, rank: "a", image: TestImages.image())])
        let id = editor.note.blocks[0].id
        editor.setImageWidth(300, of: id)
        #expect(editor.note.blocks[0].imageWidth == 300)
        editor.undo()
        #expect(editor.note.blocks[0].imageWidth == nil)
    }

    @Test func aRowsPictureIsDeletedWithoutItsRow() throws {
        let editor = try makeEditor([NoteBlock(rank: "a", content: RichText(plain: "Fix login"), image: TestImages.image())])
        let id = editor.note.blocks[0].id
        editor.deleteImage(of: id)
        #expect(editor.note.blocks.map(\.content.plainText) == ["Fix login"])
        #expect(editor.note.blocks[0].image == nil)
        editor.undo()
        #expect(editor.note.blocks[0].image != nil)
    }

    @Test func attachedPicturesAreSaved() throws {
        let deps = try AppDependencies.inMemory()
        let picture = TestImages.image()
        let note = Note(createdAt: .now, manualRank: "i", blocks: [
            NoteBlock(type: .checklistItem, rank: "a", content: RichText(plain: "Fix login"), image: picture, imageWidth: 180),
        ])
        try deps.notes.save(note)
        let loaded = try #require(try deps.notes.note(id: note.id))
        #expect(loaded.blocks[0].image?.data == picture.data && loaded.blocks[0].imageWidth == 180)
    }

    @Test func noPicturesNoChange() throws {
        let editor = try makeEditor([NoteBlock(rank: "a", content: RichText(plain: "Board"))])
        #expect(!editor.insertImages([], relativeTo: editor.note.blocks[0].id, placeAfter: true))
        #expect(!editor.canUndo)
    }

    @Test func slashImageAsksForPictures() async throws {
        let editor = try makeEditor([NoteBlock(rank: "a", content: RichText(plain: "/image"))])
        let id = editor.note.blocks[0].id
        let image = TestImages.image()
        editor.imagePicker = { [image] }
        editor.applyCompletedSlashCommand(try #require(SlashCommand.exact("image")), blockID: id, removing: 0..<6)
        for _ in 0..<50 where editor.note.blocks.count == 1 { try await Task.sleep(for: .milliseconds(10)) }
        // The emptied line becomes the picture.
        #expect(editor.note.blocks.map(\.type) == [.image])
        #expect(editor.note.blocks[0].image == image)
    }

    @Test func clickingBelowAColumnContinuesIt() throws {
        let editor = try makeEditor([NoteBlock(rank: "a", content: RichText(plain: "Left")),
                                     NoteBlock(rank: "b", content: RichText(plain: "Right"), column: 1)])
        editor.focusLastBlockEnd(column: 0)
        #expect(editor.focusRequest?.blockID == editor.note.blocks[0].id)
        editor.focusLastBlockEnd(column: 1)
        #expect(editor.focusRequest?.blockID == editor.note.blocks[1].id)
    }
}

/// The real editor with two columns and a picture.
@MainActor
@Suite(.serialized) struct ColumnsHostingTests {
    @Test func columnsSitSideBySide() async throws {
        let h = try await EditorHarness.make(blocks: [(.paragraph, RichText(plain: "Left")), (.paragraph, RichText(plain: "Right"))])
        h.editor.moveBlocks([h.editor.note.blocks[1].id], toColumn: 1)
        await h.pump()
        let left = try #require(h.textView(for: h.editor.note.blocks[0].id))
        let right = try #require(h.textView(for: h.editor.note.blocks[1].id))
        let leftFrame = left.convert(left.bounds, to: nil), rightFrame = right.convert(right.bounds, to: nil)
        #expect(rightFrame.minX > leftFrame.maxX)          // beside, not below
        #expect(abs(rightFrame.maxY - leftFrame.maxY) < 1)  // same line
    }

    @Test func pastingAScreenshotAddsAPicture() async throws {
        let h = try await EditorHarness.make(blocks: [(.paragraph, RichText(plain: "Board"))])
        let board = NSPasteboard(name: .init("SmartNotesTests-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        h.textViews.forEach { $0.pasteboard = board }
        board.clearContents()
        board.setData(TestImages.data(width: 40, height: 30, type: .tiff), forType: .tiff)
        h.click(block: 0, at: 5)
        h.focused?.paste(nil)
        await h.pump()
        #expect(h.editor.note.blocks.map(\.type) == [.paragraph, .image])
        #expect(h.plainBlocks == ["Board", ""])
    }

    /// A drag carries a small preview of what is dragged (as TIFF): the real
    /// file must win, or the note gets a thumbnail.
    @Test func theDraggedFileWinsOverItsPreview() throws {
        let board = NSPasteboard(name: .init("SmartNotesTests-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).png")
        let full = TestImages.data(width: 800, height: 600)
        try full.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        board.clearContents()
        board.writeObjects([file as NSURL])
        board.addTypes([.tiff], owner: nil)
        board.setData(TestImages.data(width: 66, height: 58, type: .tiff), forType: .tiff)

        let payload = ImageDrop.payload(from: board)
        #expect(ImageDrop.hasImages(board))
        #expect(ImageDrop.immediateData(payload) == [full])
    }

    @Test func textWithAnImageIsPastedAsText() async throws {
        let h = try await EditorHarness.make(blocks: [(.paragraph, .empty)])
        let board = NSPasteboard(name: .init("SmartNotesTests-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        h.textViews.forEach { $0.pasteboard = board }
        board.clearContents()
        board.declareTypes([.string, .png], owner: nil)
        board.setString("Hello", forType: .string)
        board.setData(TestImages.data(width: 10, height: 10), forType: .png)
        h.click(block: 0, at: 0)
        h.focused?.paste(nil)
        await h.pump()
        #expect(h.editor.note.blocks.map(\.type) == [.paragraph])
        #expect(h.plainBlocks == ["Hello"])
    }
}

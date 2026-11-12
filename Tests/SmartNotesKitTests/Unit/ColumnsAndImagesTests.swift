import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import SmartNotesKit

/// Real image files for tests, drawn in memory.
enum TestImages {
    static func data(width: Int, height: Int, type: UTType = .png, opaque: Bool = false) -> Data {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: opaque ? CGImageAlphaInfo.noneSkipLast.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0.9, green: 0.6, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        let output = NSMutableData()
        let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        CGImageDestinationFinalize(destination)
        return output as Data
    }

    static func image(width: Int = 40, height: Int = 30) -> NoteImage {
        NoteImage(data: data(width: width, height: height))!
    }
}

@Suite struct ColumnsTests {
    private func block(_ text: String, _ rank: String, column: Int = 0, type: BlockType = .paragraph) -> NoteBlock {
        NoteBlock(type: type, rank: rank, content: RichText(plain: text), column: column)
    }

    private func note(_ blocks: [NoteBlock]) -> Note {
        Note(createdAt: .now, manualRank: "i", blocks: blocks)
    }

    private func texts(_ note: Note) -> [String] { note.blocks.map(\.content.plainText) }

    @Test func blocksReadLeftColumnThenRightAndRanksRiseThatWay() {
        // The right column's ranks start below the left's: they are renumbered.
        let note = note([block("R1", "a", column: 1), block("L1", "b"), block("L2", "c"), block("R2", "d", column: 1)])
        #expect(texts(note) == ["L1", "L2", "R1", "R2"])
        #expect(note.blocks.map(\.column) == [0, 0, 1, 1])
        #expect(note.blocks.map(\.rank) == note.blocks.map(\.rank).sorted())
        #expect(note.hasColumns)
    }

    @Test func aRightColumnAloneBecomesTheOnlyColumn() {
        let note = note([block("A", "a", column: 1), block("B", "b", column: 1)])
        #expect(note.blocks.map(\.column) == [0, 0])
        #expect(!note.hasColumns)
    }

    @Test func returnInTheRightColumnContinuesThere() throws {
        let note = note([block("Left", "a"), block("Right", "b", column: 1)])
        let result = try BlockEditing.split(note, blockID: note.blocks[1].id, atUTF16Offset: 5)
        #expect(texts(result.note) == ["Left", "Right", ""])
        #expect(result.note.blocks.map(\.column) == [0, 1, 1])
    }

    @Test func returnAtTheEndOfTheLeftColumnStaysOnTheLeft() throws {
        let note = note([block("Left", "a"), block("Right", "b", column: 1)])
        let result = try BlockEditing.split(note, blockID: note.blocks[0].id, atUTF16Offset: 4)
        #expect(texts(result.note) == ["Left", "", "Right"])
        #expect(result.note.blocks.map(\.column) == [0, 0, 1])
    }

    @Test func backspaceNeverJoinsTheColumns() throws {
        let note = note([block("Left", "a"), block("Right", "b", column: 1)])
        #expect(try BlockEditing.mergeWithPrevious(note, blockID: note.blocks[1].id) == nil)

        // An empty first line of the right column goes, and the column with it.
        let empty = self.note([block("Left", "a"), block("", "b", column: 1)])
        let result = try #require(try BlockEditing.mergeWithPrevious(empty, blockID: empty.blocks[1].id))
        #expect(texts(result.note) == ["Left"])
        #expect(!result.note.hasColumns)
        #expect(result.focusBlockID == empty.blocks[0].id && result.focusOffset == 4)
    }

    @Test func moveUpAndDownStayInTheColumn() {
        let note = note([block("L", "a"), block("R1", "b", column: 1), block("R2", "c", column: 1)])
        #expect(BlockEditing.move(note, blockID: note.blocks[0].id, by: 1) == nil)
        #expect(BlockEditing.move(note, blockID: note.blocks[1].id, by: -1) == nil)
        let moved = BlockEditing.move(note, blockID: note.blocks[1].id, by: 1)
        #expect(moved.map(texts) == ["L", "R2", "R1"])
    }

    @Test func draggingOntoARowOfTheOtherColumnMovesThere() throws {
        let note = note([block("L1", "a"), block("L2", "b"), block("R1", "c", column: 1)])
        let moved = try #require(BlockEditing.move(note, blockID: note.blocks[0].id, relativeTo: note.blocks[2].id, placeAfter: false))
        #expect(texts(moved) == ["L2", "L1", "R1"])
        #expect(moved.blocks.map(\.column) == [0, 1, 1])
        // Same order, other column: still a change.
        let back = try #require(BlockEditing.move(moved, blockID: moved.blocks[1].id, relativeTo: moved.blocks[0].id, placeAfter: true))
        #expect(texts(back) == ["L2", "L1", "R1"])
        #expect(back.blocks.map(\.column) == [0, 0, 1])
    }

    @Test func movingToTheRightColumnStartsItAndEmptyingTheLeftEndsIt() throws {
        let note = note([block("A", "a"), block("B", "b"), block("C", "c")])
        let split = try #require(BlockEditing.moveToColumn(note, blockIDs: [note.blocks[0].id], column: 1))
        #expect(texts(split) == ["B", "C", "A"])
        #expect(split.blocks.map(\.column) == [0, 0, 1])
        // Goes to the end of the column, in order.
        let more = try #require(BlockEditing.moveToColumn(split, blockIDs: [split.blocks[1].id, split.blocks[0].id], column: 1))
        #expect(texts(more) == ["A", "B", "C"])
        #expect(!more.hasColumns)
        #expect(BlockEditing.moveToColumn(more, blockIDs: [more.blocks[0].id], column: 0) == nil)
    }

    @Test func sortingKeepsEachColumnsListsApart() throws {
        let note = note([
            NoteBlock(type: .checklistItem, rank: "a", content: RichText(plain: "L low"), tag: .priority(.low)),
            NoteBlock(type: .checklistItem, rank: "b", content: RichText(plain: "L high"), tag: .priority(.high)),
            NoteBlock(type: .checklistItem, rank: "c", content: RichText(plain: "R low"), tag: .priority(.low), column: 1),
            NoteBlock(type: .checklistItem, rank: "d", content: RichText(plain: "R high"), tag: .priority(.high), column: 1),
        ])
        let sorted = try #require(BlockEditing.sortRows(note, by: .severity))
        #expect(texts(sorted) == ["L high", "L low", "R high", "R low"])
        #expect(sorted.blocks.map(\.column) == [0, 0, 1, 1])
        // A selection across both columns sorts each column's part.
        let selected = try #require(BlockEditing.sortRows(note, by: .severity, within: Set(note.blocks.map(\.id))))
        #expect(texts(selected) == ["L high", "L low", "R high", "R low"])
    }

    @Test func slashColumnMovesTheBlockAcross() throws {
        let note = note([block("A", "a"), block("B /column", "b")])
        let result = try BlockEditing.applySlashCommand(note, blockID: note.blocks[1].id, removing: 1..<9, action: .otherColumn)
        #expect(texts(result.note) == ["A", "B"])
        #expect(result.note.blocks.map(\.column) == [0, 1])
    }

    @Test func columnsGroupBlocksForDisplay() {
        let note = note([block("L", "a"), block("R1", "b", column: 1), block("R2", "c", column: 1)])
        #expect(BlockEditing.columns(of: note).map { $0.map(\.content.plainText) } == [["L"], ["R1", "R2"]])
    }
}

@Suite struct ImageBlockTests {
    private func note(_ blocks: [NoteBlock]) -> Note {
        Note(createdAt: .now, manualRank: "i", blocks: blocks)
    }

    @Test func droppedPicturesTakeTheirPlaceAfterARow() throws {
        let note = note([NoteBlock(rank: "a", content: RichText(plain: "Moodboard")), NoteBlock(rank: "b", content: RichText(plain: "End"))])
        let images = [TestImages.image(), TestImages.image()]
        let result = try #require(BlockEditing.insertImages(note, images, relativeTo: note.blocks[0].id, placeAfter: true))
        #expect(result.note.blocks.map(\.type) == [.paragraph, .image, .image, .paragraph])
        #expect(result.note.blocks.compactMap(\.image?.id) == images.map(\.id))
        #expect(result.focusBlockID == result.note.blocks[2].id) // ready for a caption
    }

    @Test func aPictureDroppedOnAnEmptyLineReplacesIt() throws {
        let note = note([NoteBlock(rank: "a", content: RichText(plain: "Title")), NoteBlock(rank: "b")])
        let result = try #require(BlockEditing.insertImages(note, [TestImages.image()], relativeTo: note.blocks[1].id, placeAfter: true))
        #expect(result.note.blocks.map(\.type) == [.paragraph, .image])
    }

    @Test func picturesTakeTheColumnTheyAreDroppedIn() throws {
        let note = note([NoteBlock(rank: "a", content: RichText(plain: "L")), NoteBlock(rank: "b", content: RichText(plain: "R"), column: 1)])
        let result = try #require(BlockEditing.insertImages(note, [TestImages.image()], relativeTo: note.blocks[1].id, placeAfter: false))
        #expect(result.note.blocks.map(\.type) == [.paragraph, .image, .paragraph])
        #expect(result.note.blocks.map(\.column) == [0, 1, 1])
    }

    @Test func picturesDroppedBesideTheNoteStartTheRightColumn() throws {
        let note = note([NoteBlock(rank: "a", content: RichText(plain: "Text"))])
        let result = try #require(BlockEditing.insertImagesInNewColumn(note, [TestImages.image()]))
        #expect(result.note.blocks.map(\.column) == [0, 1])
        #expect(result.note.blocks[1].type == .image)
        #expect(BlockEditing.insertImagesInNewColumn(result.note, [TestImages.image()]) == nil) // already two columns
    }

    @Test func backspaceRemovesAPictureOnlyWithoutACaption() throws {
        let image = NoteBlock(type: .image, rank: "b", image: TestImages.image())
        let note = note([NoteBlock(rank: "a", content: RichText(plain: "Above")), image])
        let removed = try #require(try BlockEditing.mergeWithPrevious(note, blockID: image.id))
        #expect(removed.note.blocks.map(\.type) == [.paragraph])
        #expect(removed.focusBlockID == note.blocks[0].id && removed.focusOffset == 5)

        var captioned = image
        captioned.content = RichText(plain: "Caption")
        #expect(try BlockEditing.mergeWithPrevious(self.note([note.blocks[0], captioned]), blockID: image.id) == nil)
    }

    @Test func backspaceAfterAPictureGoesToItsCaption() throws {
        let image = NoteBlock(type: .image, rank: "a", content: RichText(plain: "Cap"), image: TestImages.image())
        let text = NoteBlock(rank: "b", content: RichText(plain: "Next"))
        let note = note([image, text])
        let result = try #require(try BlockEditing.mergeWithPrevious(note, blockID: text.id))
        #expect(result.note == note) // the text doesn't join the picture
        #expect(result.focusBlockID == image.id && result.focusOffset == 3)

        let empty = NoteBlock(rank: "b")
        let gone = try #require(try BlockEditing.mergeWithPrevious(self.note([image, empty]), blockID: empty.id))
        #expect(gone.note.blocks.map(\.id) == [image.id])
    }

    @Test func picturesKeepTheirKind() {
        let image = NoteBlock(type: .image, rank: "b", image: TestImages.image())
        let note = note([NoteBlock(rank: "a", content: RichText(plain: "Row")), image])
        #expect(BlockEditing.setType(note, blockID: image.id, to: .heading1) == nil)
        #expect(BlockEditing.setType(note, blockID: note.blocks[0].id, to: .image) == nil)
    }

    @Test func aPictureDroppedOnARowIsAttachedToIt() throws {
        let picture = TestImages.image()
        let image = NoteBlock(type: .image, rank: "b", content: RichText(plain: "Login screen"), image: picture, imageWidth: 200)
        let note = note([NoteBlock(type: .checklistItem, rank: "a", content: RichText(plain: "Fix login")), image])
        let attached = try #require(BlockEditing.nest(note, blockID: image.id, into: note.blocks[0].id))
        #expect(attached.blocks.count == 1)
        #expect(attached.blocks[0].image == picture && attached.blocks[0].imageWidth == 200)
        #expect(attached.blocks[0].detail.plainText == "Login screen") // the caption isn't lost
        // A row holds one picture; pictures don't take pictures.
        #expect(!BlockEditing.canAttachImage(attached, to: attached.blocks[0].id))
        #expect(!BlockEditing.canAttachImage(note, to: image.id))
    }

    @Test func aRowsPictureMovesOrComesOutAsABlock() throws {
        let picture = TestImages.image()
        let note = note([
            NoteBlock(rank: "a", content: RichText(plain: "One"), image: picture, imageWidth: 150),
            NoteBlock(rank: "b", content: RichText(plain: "Two")),
        ])
        let moved = try #require(BlockEditing.moveAttachedImage(note, from: note.blocks[0].id, to: note.blocks[1].id))
        #expect(moved.blocks.map { $0.image != nil } == [false, true])
        #expect(moved.blocks[1].imageWidth == 150)

        let out = try #require(BlockEditing.detachImage(note, from: note.blocks[0].id, relativeTo: note.blocks[1].id, placeAfter: true))
        #expect(out.note.blocks.map(\.type) == [.paragraph, .paragraph, .image])
        #expect(out.note.blocks[0].image == nil)
        #expect(out.note.blocks[2].image == picture && out.note.blocks[2].imageWidth == 150)
        #expect(out.focusBlockID == out.note.blocks[2].id)

        let removed = try #require(BlockEditing.removeAttachedImage(note, from: note.blocks[0].id))
        #expect(removed.blocks.map(\.content.plainText) == ["One", "Two"] && removed.blocks[0].image == nil)
    }

    @Test func joiningRowsKeepsTheirPicture() throws {
        let picture = TestImages.image()
        let note = note([NoteBlock(rank: "a", content: RichText(plain: "One")),
                         NoteBlock(rank: "b", content: RichText(plain: "Two"), image: picture)])
        let joined = try #require(try BlockEditing.mergeWithPrevious(note, blockID: note.blocks[1].id))
        #expect(joined.note.blocks.count == 1 && joined.note.blocks[0].image == picture)

        var both = note
        both.blocks[0].image = TestImages.image()
        #expect(try BlockEditing.mergeWithPrevious(both, blockID: both.blocks[1].id) == nil)
    }

    @Test func pastedPicturesGoInBelowTheLine() throws {
        let note = note([NoteBlock(rank: "a", content: RichText(plain: "Hello world"))])
        let image = TestImages.image()
        let result = try #require(try BlockEditing.paste(note, blockID: note.blocks[0].id, range: 5..<5,
                                                         paragraphs: [PastedParagraph(type: .image, content: .empty, image: image)]))
        #expect(result.note.blocks.map(\.content.plainText) == ["Hello world", ""])
        #expect(result.note.blocks[1].image == image)
    }

    @Test func copyingAPictureKeepsIt() {
        let image = NoteBlock(type: .image, rank: "b", content: RichText(plain: "Cap"), image: TestImages.image())
        let note = note([NoteBlock(rank: "a", content: RichText(plain: "Row")), image])
        let copied = BlockEditing.copiedParagraphs(note, selection: BlockRangeSelection(
            anchor: BlockPosition(blockID: note.blocks[0].id, offset: 0), focus: BlockPosition(blockID: image.id, offset: 3)
        ))
        #expect(copied.last?.image == image.image)
        #expect(copied.last?.type == .image)
    }

    @Test func deletingTheOnlyBlockLeavesAFreshLine() throws {
        let image = NoteBlock(type: .image, rank: "a", image: TestImages.image())
        let result = try #require(BlockEditing.removing(note([image]), blockID: image.id))
        #expect(result.note.blocks.map(\.type) == [.paragraph])
        #expect(result.focusBlockID == result.note.blocks[0].id)
    }

    @Test func picturesCanBeResized() throws {
        let image = NoteBlock(type: .image, rank: "a", image: TestImages.image())
        let note = note([image])
        let resized = try #require(BlockEditing.setImageWidth(note, blockID: image.id, to: 320.4))
        #expect(resized.blocks[0].imageWidth == 320)
        #expect(BlockEditing.setImageWidth(resized, blockID: image.id, to: 320) == nil)       // no change
        #expect(BlockEditing.setImageWidth(resized, blockID: image.id, to: 5)?.blocks[0].imageWidth == 32) // never vanishes
        #expect(BlockEditing.setImageWidth(resized, blockID: image.id, to: nil)?.blocks[0].imageWidth == nil)
        let text = self.note([NoteBlock(rank: "a", content: RichText(plain: "Text"))])
        #expect(BlockEditing.setImageWidth(text, blockID: text.blocks[0].id, to: 100) == nil)
    }

    @Test func exportsKeepThePictureAndColumn() throws {
        let image = TestImages.image()
        var note = note([NoteBlock(rank: "a", content: RichText(plain: "L")),
                         NoteBlock(type: .image, rank: "b", content: RichText(plain: "Sketch"), column: 1, image: image, imageWidth: 300)])
        note.title = "Board"
        let data = try NoteExport.json([note], exportedAt: .now)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let blocks = try decoder.decode(NoteExport.Document.self, from: data).notes[0].blocks
        #expect(blocks.map(\.column) == [nil, 1])
        #expect(blocks[1].image == image.data)
        #expect(blocks[1].imageWidth == 300)
        #expect(NoteExport.markdown(note).contains("*[Image: Sketch]*"))
    }
}

@Suite struct NoteImageTests {
    @Test func readsOnlyImages() {
        #expect(NoteImage(data: Data("not an image".utf8)) == nil)
        #expect(NoteImage.importing(Data("nope".utf8)) == nil)
        #expect(NoteImage.pixelSize(of: TestImages.data(width: 40, height: 30)) == CGSize(width: 40, height: 30))
    }

    @Test func smallCompactPicturesAreKeptAsTheyAre() throws {
        let data = TestImages.data(width: 40, height: 30)
        #expect(try #require(NoteImage.importing(data)).data == data)
    }

    @Test func largePicturesAreScaledDown() throws {
        let image = try #require(NoteImage.importing(TestImages.data(width: 400, height: 200), maxPixelSize: 100))
        #expect(NoteImage.pixelSize(of: image.data) == CGSize(width: 100, height: 50))
    }

    @Test func tiffBecomesACompactFormat() throws {
        let tiff = TestImages.data(width: 40, height: 30, type: .tiff, opaque: true)
        let image = try #require(NoteImage.importing(tiff))
        let source = try #require(CGImageSourceCreateWithData(image.data as CFData, nil))
        #expect(CGImageSourceGetType(source) as String? == UTType.jpeg.identifier)
        #expect(NoteImage.pixelSize(of: image.data) == CGSize(width: 40, height: 30))
    }
}

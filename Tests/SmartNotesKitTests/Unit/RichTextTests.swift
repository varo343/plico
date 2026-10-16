import Foundation
import Testing
@testable import SmartNotesKit

@Suite struct RichTextTests {
    @Test func normalizationMergesAdjacentRunsAndDropsEmpty() {
        let text = RichText(runs: [
            TextRun("Hel", marks: [.bold]),
            TextRun("", marks: [.italic]),
            TextRun("lo", marks: [.bold]),
            TextRun(" world"),
        ])
        #expect(text.runs == [TextRun("Hello", marks: [.bold]), TextRun(" world")])
        #expect(text.plainText == "Hello world")
    }

    @Test func emptyTextHasNoRuns() {
        #expect(RichText(plain: "").isEmpty)
        #expect(RichText.empty.plainText == "")
    }

    @Test func roundTripPreservesAllAttributes() throws {
        let original = RichText(runs: [
            TextRun("Bold italic", marks: [.bold, .italic]),
            TextRun(" link", link: URL(string: "https://example.com/a?b=c")),
            TextRun(" serif", fontFamily: .serif, fontSize: .title),
            TextRun(" struck\nsoft break", marks: [.strikethrough, .underline, .code]),
        ])
        let decoded = try RichText.decode(from: try original.encodedData())
        #expect(decoded == original)
    }

    @Test func encodingIsDeterministicAndMatchesDocumentedShape() throws {
        let text = RichText(runs: [TextRun("Hi", marks: [.underline, .bold, .italic])])
        let json = String(decoding: try text.encodedData(), as: UTF8.self)
        #expect(json == #"{"runs":[{"marks":["bold","italic","underline"],"text":"Hi"}],"version":1}"#)
        // Same content always encodes to identical bytes.
        #expect(try text.encodedData() == RichText(runs: [TextRun("Hi", marks: [.bold, .italic, .underline])]).encodedData())
    }

    @Test func decodesMinimalVersion1Payload() throws {
        let data = Data(#"{"version":1,"runs":[{"text":"plain"}]}"#.utf8)
        #expect(try RichText.decode(from: data) == RichText(plain: "plain"))
    }

    @Test func rejectsUnknownFutureVersion() {
        let data = Data(#"{"version":2,"runs":[]}"#.utf8)
        #expect(throws: RichTextCodingError.unsupportedVersion(2)) { try RichText.decode(from: data) }
    }

    @Test func rejectsUnknownMarkInsteadOfDroppingIt() {
        let data = Data(#"{"version":1,"runs":[{"text":"x","marks":["sparkle"]}]}"#.utf8)
        #expect(throws: DecodingError.self) { try RichText.decode(from: data) }
    }
}

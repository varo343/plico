import AppKit
import SwiftUI
import Testing
@testable import SmartNotesKit

/// Drives the real editor (SwiftUI + per-block NSTextViews) in an offscreen
/// window with synthesized key events, exercising the same AppKit path as typing.
@MainActor
final class EditorHarness {
    let window: NSWindow
    let editor: NoteEditorModel
    let deps: AppDependencies

    init(blocks: [(BlockType, RichText)]) throws {
        deps = try AppDependencies.inMemory()
        let ranks = Rank.evenlySpaced(blocks.count)
        let note = Note(createdAt: .now, manualRank: "i", blocks: zip(blocks, ranks).map {
            NoteBlock(type: $0.0, rank: $1, content: $0.1)
        })
        try deps.notes.save(note)
        editor = NoteEditorModel(note: note, repository: deps.notes, autosaveDelay: .seconds(60))
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: NoteEditorView(model: editor))
    }

    deinit {
        MainActor.assumeIsolated { window.close() }
    }

    /// Yields the main actor so queued main-queue work (deferred focus) and
    /// SwiftUI updates run, as they would between real events.
    /// Waits until the UI reflects the model: suspending hands the main thread
    /// back to its run loop and dispatch queue. Waiting on state rather than a
    /// fixed delay keeps the tests reliable when the suite runs in parallel.
    func pump() async {
        let deadline = ContinuousClock.now + .seconds(5)
        repeat {
            try? await Task.sleep(for: .milliseconds(10))
        } while !isSettled && ContinuousClock.now < deadline
    }

    private var isSettled: Bool {
        let views = textViews
        guard views.count == editor.note.blocks.count,
              views.map(\.string) == plainBlocks,
              !views.contains(where: { $0.pendingFocusOffset != nil })
        else { return false }
        if let request = editor.focusRequest, let index = editor.note.blocks.firstIndex(where: { $0.id == request.blockID }) {
            return focused === views[index]
        }
        return true
    }

    /// Block text views in top-to-bottom order.
    var textViews: [BlockNSTextView] {
        func collect(_ view: NSView) -> [BlockNSTextView] {
            (view as? BlockNSTextView).map { [$0] } ?? view.subviews.flatMap(collect)
        }
        return collect(window.contentView!).sorted {
            $0.convert($0.bounds, to: nil).maxY > $1.convert($1.bounds, to: nil).maxY
        }
    }

    var focused: BlockNSTextView? { window.firstResponder as? BlockNSTextView }

    func click(block index: Int, at offset: Int) {
        let view = textViews[index]
        editor.focusRequest = nil // a click replaces any earlier programmatic focus
        window.makeFirstResponder(view)
        view.setSelectedRange(NSRange(location: offset, length: 0))
    }

    func type(_ text: String) async {
        for character in text {
            await send(String(character), keyCode: 0)
        }
    }

    func pressReturn(shift: Bool = false) async { await send("\r", keyCode: 36, modifiers: shift ? .shift : []) }
    func pressBackspace() async { await send("\u{7f}", keyCode: 51) }
    func pressUp() async { await send(String(UnicodeScalar(NSUpArrowFunctionKey)!), keyCode: 126, modifiers: [.function, .numericPad]) }
    func pressDown() async { await send(String(UnicodeScalar(NSDownArrowFunctionKey)!), keyCode: 125, modifiers: [.function, .numericPad]) }

    private func send(_ characters: String, keyCode: UInt16, modifiers: NSEvent.ModifierFlags = []) async {
        let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: characters,
            charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode
        )!
        focused?.keyDown(with: event)
        await pump()
    }

    var plainBlocks: [String] { editor.note.blocks.map(\.content.plainText) }

    static func make(blocks: [(BlockType, RichText)]) async throws -> EditorHarness {
        let harness = try EditorHarness(blocks: blocks)
        await harness.pump()
        return harness
    }
}

@MainActor
@Suite(.serialized) struct EditorHostingTests {
    @Test func rendersOneTextViewPerBlock() async throws {
        let h = try await EditorHarness.make(blocks: [(.heading1, RichText(plain: "Title")), (.paragraph, RichText(plain: "Body")), (.checklistItem, RichText(plain: "Task"))])
        #expect(h.textViews.map(\.string) == ["Title", "Body", "Task"])
    }

    @Test func typingUpdatesModelAndPersists() async throws {
        let h = try await EditorHarness.make(blocks: [(.paragraph, .empty)])
        h.click(block: 0, at: 0)
        await h.type("Hello")
        #expect(h.plainBlocks == ["Hello"])
        h.editor.flush()
        #expect(try h.deps.notes.note(id: h.editor.note.id)?.blocks.first?.content.plainText == "Hello")
    }

    @Test func typingInsideBoldRunStaysBoldAndOtherRunsUntouched() async throws {
        let h = try await EditorHarness.make(blocks: [(.paragraph, RichText(runs: [TextRun("plain "), TextRun("bold", marks: [.bold]), TextRun(" end", marks: [.italic])]))])
        h.click(block: 0, at: 8) // between "bo" and "ld"
        await h.type("XY")
        #expect(h.editor.note.blocks[0].content.runs == [
            TextRun("plain "), TextRun("boXYld", marks: [.bold]), TextRun(" end", marks: [.italic]),
        ])
    }

    @Test func returnSplitsAndMovesCaretToNewBlock() async throws {
        let h = try await EditorHarness.make(blocks: [(.paragraph, RichText(plain: "HelloWorld"))])
        h.click(block: 0, at: 5)
        await h.pressReturn()
        await h.pump()
        #expect(h.plainBlocks == ["Hello", "World"])
        #expect(h.textViews.map(\.string) == ["Hello", "World"])
        #expect(h.focused === h.textViews[1])
        await h.type("New ")
        #expect(h.plainBlocks == ["Hello", "New World"])
    }

    @Test func backspaceAtStartMergesAndKeepsCaretAtJoin() async throws {
        let h = try await EditorHarness.make(blocks: [(.paragraph, RichText(plain: "Hello")), (.paragraph, RichText(plain: "World"))])
        h.click(block: 1, at: 0)
        await h.pressBackspace()
        await h.pump()
        #expect(h.plainBlocks == ["HelloWorld"])
        #expect(h.textViews.count == 1)
        await h.type("_")
        #expect(h.plainBlocks == ["Hello_World"])
    }

    @Test func shiftReturnInsertsSoftBreakInSameBlock() async throws {
        let h = try await EditorHarness.make(blocks: [(.paragraph, RichText(plain: "ab"))])
        h.click(block: 0, at: 1)
        await h.pressReturn(shift: true)
        #expect(h.plainBlocks == ["a\nb"])
    }

    @Test func returnInChecklistContinuesList() async throws {
        let h = try await EditorHarness.make(blocks: [(.checklistItem, RichText(plain: "Milk"))])
        h.click(block: 0, at: 4)
        await h.pressReturn()
        await h.pump()
        await h.type("Eggs")
        #expect(h.editor.note.blocks.map(\.type) == [.checklistItem, .checklistItem])
        #expect(h.plainBlocks == ["Milk", "Eggs"])
    }

    @Test func arrowKeysMoveBetweenBlocks() async throws {
        let h = try await EditorHarness.make(blocks: [(.paragraph, RichText(plain: "First")), (.paragraph, RichText(plain: "Second"))])
        h.click(block: 1, at: 3)
        await h.pressUp()
        await h.pump()
        #expect(h.focused === h.textViews[0])
        #expect(h.focused?.selectedRange().location == 5) // end of previous block
        await h.pressDown()
        await h.pump()
        #expect(h.focused === h.textViews[1])
        #expect(h.focused?.selectedRange().location == 0)
    }

    @Test func pastingRichTextKeepsTextAsPlain() async throws {
        let h = try await EditorHarness.make(blocks: [(.paragraph, RichText(plain: "A"))])
        h.click(block: 0, at: 1)
        let board = NSPasteboard(name: .init("SmartNotesTests-\(UUID().uuidString)"))
        board.clearContents()
        board.writeObjects([NSAttributedString(string: " pasted", attributes: [.font: NSFont.boldSystemFont(ofSize: 40)])])
        // pasteAsPlainText reads the general pasteboard; use it for this test only.
        let general = NSPasteboard.general
        let saved = general.pasteboardItems?.compactMap { $0.string(forType: .string) }
        general.clearContents()
        general.writeObjects([NSAttributedString(string: " pasted", attributes: [.font: NSFont.boldSystemFont(ofSize: 40)])])
        h.focused?.paste(nil)
        await h.pump()
        #expect(h.editor.note.blocks[0].content == RichText(plain: "A pasted"))
        general.clearContents()
        if let saved, !saved.isEmpty { general.setString(saved.joined(), forType: .string) }
        _ = board
    }

    @Test func largeNoteEditingStaysResponsive() async throws {
        let blocks = (0..<150).map { (BlockType.paragraph, RichText(runs: [TextRun("Paragraph \($0) "), TextRun("bold", marks: [.bold])])) }
        let clock = ContinuousClock()
        var start = clock.now
        let h = try await EditorHarness.make(blocks: blocks)
        let loadTime = clock.now - start
        h.click(block: 0, at: 0)
        start = clock.now
        await h.type("abcdefghij")
        let typingTime = clock.now - start
        #expect(h.plainBlocks[0].hasPrefix("abcdefghij"))
        // Coarse regression guards (each step includes at least 10 ms of waiting).
        #expect(loadTime < .seconds(3))
        #expect(typingTime < .seconds(3))
        print("150-block note: load \(loadTime), 10 keystrokes \(typingTime)")
    }
}

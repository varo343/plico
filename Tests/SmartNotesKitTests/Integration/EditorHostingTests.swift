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

    func select(block index: Int, range: Range<Int>) {
        click(block: index, at: range.lowerBound)
        textViews[index].setSelectedRange(NSRange(location: range.lowerBound, length: range.count))
    }

    func pressTab(shift: Bool = false) async {
        await send(shift ? "\u{19}" : "\t", keyCode: 48, modifiers: shift ? .shift : [])
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

    // MARK: Milestone 2

    @Test func boldThroughResponderChainKeepsSelection() async throws {
        let h = try await EditorHarness.make(blocks: [(.paragraph, RichText(plain: "Hello world"))])
        h.select(block: 0, range: 0..<5)
        h.focused?.snToggleBold(nil)
        await h.pump()
        #expect(h.editor.note.blocks[0].content.runs == [TextRun("Hello", marks: [.bold]), TextRun(" world")])
        #expect(h.focused?.selectedRange() == NSRange(location: 0, length: 5))
        let font = h.textViews[0].textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        #expect(font?.fontDescriptor.symbolicTraits.contains(.bold) == true)
    }

    @Test func boldWithCaretOnlyAppliesToNextTyping() async throws {
        let h = try await EditorHarness.make(blocks: [(.paragraph, RichText(plain: "ab"))])
        h.click(block: 0, at: 1)
        h.focused?.snToggleItalic(nil)
        await h.type("X")
        #expect(h.editor.note.blocks[0].content.runs == [TextRun("a"), TextRun("X", marks: [.italic]), TextRun("b")])
    }

    @Test func tabIndentsListItemsOnly() async throws {
        let h = try await EditorHarness.make(blocks: [(.bulletItem, RichText(plain: "item"))])
        h.click(block: 0, at: 2)
        await h.pressTab()
        #expect(h.editor.note.blocks[0].indentLevel == 1)
        #expect(h.plainBlocks == ["item"]) // no tab character inserted
        await h.pressTab(shift: true)
        #expect(h.editor.note.blocks[0].indentLevel == 0)
    }

    @Test func undoAndRedoThroughTextViewAcrossBlocks() async throws {
        let h = try await EditorHarness.make(blocks: [(.paragraph, RichText(plain: "One"))])
        h.click(block: 0, at: 3)
        await h.type("!")
        await h.pressReturn()
        await h.type("Two")
        #expect(h.plainBlocks == ["One!", "Two"])

        h.focused?.undo(nil); await h.pump()
        #expect(h.plainBlocks == ["One!", ""])
        h.focused?.undo(nil); await h.pump()
        #expect(h.plainBlocks == ["One!"])
        #expect(h.textViews.map(\.string) == ["One!"])
        h.focused?.undo(nil); await h.pump()
        #expect(h.plainBlocks == ["One"])
        h.focused?.redo(nil); await h.pump()
        h.focused?.redo(nil); await h.pump()
        #expect(h.plainBlocks == ["One!", ""])
        #expect(h.focused === h.textViews.last)
    }

    @Test func undoMenuValidationFollowsModel() async throws {
        let h = try await EditorHarness.make(blocks: [(.paragraph, RichText(plain: "a"))])
        h.click(block: 0, at: 1)
        let undoItem = NSMenuItem(title: "Undo", action: #selector(BlockNSTextView.undo(_:)), keyEquivalent: "")
        #expect(h.focused?.validateUserInterfaceItem(undoItem) == false)
        await h.type("b")
        #expect(h.focused?.validateUserInterfaceItem(undoItem) == true)
    }

    @Test func copyPasteInsideAppIsLossless() async throws {
        let h = try await EditorHarness.make(blocks: [
            (.paragraph, RichText(runs: [TextRun("code", marks: [.code], fontFamily: .monospaced), TextRun(" and "), TextRun("serif", fontFamily: .serif, fontSize: .large)])),
            (.paragraph, RichText(plain: "target: ")),
        ])
        let board = NSPasteboard(name: .init("SmartNotesTests-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        h.textViews.forEach { $0.pasteboard = board }
        h.select(block: 0, range: 0..<18)
        h.focused?.copy(nil)
        #expect(board.types?.contains(.rtf) == true)        // other apps still get RTF
        h.click(block: 1, at: 8)
        h.focused?.paste(nil)
        await h.pump()
        #expect(h.editor.note.blocks[1].content == RichText(plain: "target: ") + h.editor.note.blocks[0].content)
    }

    @Test func multiParagraphPasteCreatesBlocksAndFocusesEnd() async throws {
        let h = try await EditorHarness.make(blocks: [(.paragraph, RichText(plain: "[]"))])
        let board = NSPasteboard(name: .init("SmartNotesTests-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        board.clearContents()
        board.setString("<p>first <b>bold</b></p><ul><li>item</li></ul>", forType: .html)
        h.textViews.forEach { $0.pasteboard = board }
        h.click(block: 0, at: 1)
        h.focused?.paste(nil)
        await h.pump()
        #expect(h.plainBlocks.map { $0.trimmingCharacters(in: .whitespaces) } == ["[first bold", "item]"])
        #expect(h.editor.note.blocks[1].type == .bulletItem)
        #expect(h.focused === h.textViews[1])
        h.focused?.undo(nil); await h.pump()
        #expect(h.plainBlocks == ["[]"])
    }

    @Test func moveBlockKeepsCaretInMovedBlock() async throws {
        let h = try await EditorHarness.make(blocks: [(.paragraph, RichText(plain: "first")), (.paragraph, RichText(plain: "second"))])
        h.click(block: 1, at: 3)
        h.editor.updateSelection(blockID: h.editor.note.blocks[1].id, range: 3..<3)
        h.editor.moveBlock(by: -1)
        await h.pump()
        #expect(h.textViews.map(\.string) == ["second", "first"])
        #expect(h.focused === h.textViews[0])
        #expect(h.focused?.selectedRange().location == 3)
        await h.type("X")
        #expect(h.plainBlocks == ["secXond", "first"])
    }
}

@MainActor
@Suite(.serialized) struct EditorLayoutTests {
    /// Regression: in the real three-column layout, SwiftUI measures blocks at
    /// several candidate widths; a block must end up sized for its final width.
    @Test(arguments: [820.0, 1000, 1240])
    func blocksNeverOverlapInRealLayout(windowWidth: Double) async throws {
        let app = AppModel(dependencies: try AppDependencies.inMemory(seedSampleData: true))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: windowWidth, height: 700), styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = NSHostingView(rootView: RootView(app: app))
        try? await Task.sleep(for: .milliseconds(700))

        func collect(_ view: NSView) -> [BlockNSTextView] {
            (view as? BlockNSTextView).map { [$0] } ?? view.subviews.flatMap(collect)
        }
        let views = collect(window.contentView!).sorted {
            $0.convert($0.bounds, to: nil).maxY > $1.convert($1.bounds, to: nil).maxY
        }
        #expect(views.count >= 5)
        for view in views {
            // Text must be laid out at the width it is displayed at.
            #expect(abs((view.textContainer?.size.width ?? 0) - view.bounds.width) < 0.5, "layout width differs from frame: \(view.string.prefix(20))")
            let needed = view.height(forWidth: view.bounds.width, minimumLineHeight: 0)
            #expect(view.bounds.height + 1.5 >= needed, "block too short for its text: \(view.string.prefix(20))")
        }
        let frames = views.map { $0.convert($0.bounds, to: nil) }
        for (upper, lower) in zip(frames, frames.dropFirst()) {
            #expect(upper.minY >= lower.maxY - 0.5, "blocks overlap")
        }
    }
}

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
        // Generous: under a loaded parallel run the main actor can be busy for
        // over 5 s, and giving up early let tests index text views not yet built.
        // A settled UI returns at once, so this costs nothing normally.
        let deadline = ContinuousClock.now + .seconds(20)
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
        let nested = nestedTextViews
        guard nested.count == editor.expandedDetails.count,
              nested.allSatisfy({ view in editor.note.blocks.first { $0.id == view.blockID }?.detail.plainText == view.string })
        else { return false }
        if let request = editor.focusRequest, let index = editor.note.blocks.firstIndex(where: { $0.id == request.blockID }) {
            if request.isDetail { return focused === nested.first { $0.blockID == request.blockID } }
            return focused === views[index]
        }
        return true
    }

    /// Block text views in top-to-bottom order (nested text excluded).
    var textViews: [BlockNSTextView] {
        allTextViews.filter { !$0.isNestedText }
    }

    /// Text views of expanded nested text, top to bottom.
    var nestedTextViews: [BlockNSTextView] {
        allTextViews.filter(\.isNestedText)
    }

    private var allTextViews: [BlockNSTextView] {
        func collect(_ view: NSView) -> [BlockNSTextView] {
            (view as? BlockNSTextView).map { [$0] } ?? view.subviews.flatMap(collect)
        }
        // In the note's order (left column, then right), else top to bottom.
        let order = Dictionary(editor.note.blocks.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        return collect(window.contentView!).sorted {
            if let a = $0.blockID.flatMap({ order[$0] }), let b = $1.blockID.flatMap({ order[$0] }), a != b { return a < b }
            return $0.convert($0.bounds, to: nil).maxY > $1.convert($1.bounds, to: nil).maxY
        }
    }

    /// A block's own text view (not its nested text).
    func textView(for blockID: UUID) -> BlockNSTextView? {
        textViews.first { $0.blockID == blockID }
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

    func pressEscape() async { await send("\u{1b}", keyCode: 53) }

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
        #expect(board.data(forType: .rtf)?.isEmpty == false) // other apps still get RTF
        #expect(board.string(forType: .string) == "code and serif")
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

        func collect(_ view: NSView) -> [BlockNSTextView] {
            (view as? BlockNSTextView).map { [$0] } ?? view.subviews.flatMap(collect)
        }
        // Wait for the editor to lay out (parallel suite: no fixed delay; generous, see pump()).
        let deadline = ContinuousClock.now + .seconds(20)
        while collect(window.contentView!).filter({ $0.bounds.width > 0 }).count < 5, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(30))
        }
        try? await Task.sleep(for: .milliseconds(200))
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

@MainActor
@Suite(.serialized) struct SlashCommandHostingTests {
    @Test func typingSlashFiltersAndReturnApplies() async throws {
        let h = try await EditorHarness.make(blocks: [(.paragraph, .empty)])
        h.click(block: 0, at: 0)
        await h.type("/")
        // Everything except "Remove tag": the block has no tag.
        #expect(h.editor.slashMenu?.commands.count == SlashCommand.all.count - 1)
        await h.type("che")
        #expect(h.editor.slashMenu?.commands.map(\.name) == ["checkbox"])
        await h.pressReturn()
        #expect(h.editor.slashMenu == nil)
        #expect(h.editor.note.blocks.map(\.type) == [.checklistItem])
        #expect(h.plainBlocks == [""])           // the typed "/che" is removed
        await h.type("Milk")
        #expect(h.plainBlocks == ["Milk"])       // caret stays in the block
    }

    @Test func fullCommandWithSpaceAppliesWithoutMenu() async throws {
        let h = try await EditorHarness.make(blocks: [(.paragraph, .empty)])
        h.click(block: 0, at: 0)
        await h.type("/bullet ")
        #expect(h.editor.note.blocks[0].type == .bulletItem)
        #expect(h.plainBlocks == [""])
        await h.type("Eggs")
        #expect(h.plainBlocks == ["Eggs"])
    }

    @Test func arrowsMoveHighlightInsteadOfCaret() async throws {
        let h = try await EditorHarness.make(blocks: [(.paragraph, RichText(plain: "above")), (.paragraph, .empty)])
        h.click(block: 1, at: 0)
        await h.type("/h")
        #expect(h.editor.slashMenu?.commands.map(\.name).prefix(3) == ["h1", "h2", "h3"])
        await h.pressDown()
        #expect(h.editor.slashMenu?.highlighted == 1)
        #expect(h.focused === h.textViews[1])    // didn't jump to the block above/below
        await h.pressReturn()
        #expect(h.editor.note.blocks[1].type == .heading2)
    }

    @Test func escapeClosesMenuAndKeepsText() async throws {
        let h = try await EditorHarness.make(blocks: [(.paragraph, .empty)])
        h.click(block: 0, at: 0)
        await h.type("/che")
        await h.pressEscape()
        #expect(h.editor.slashMenu == nil)
        #expect(h.plainBlocks == ["/che"])
        await h.type("x")                        // stays dismissed for this "/"
        #expect(h.editor.slashMenu == nil)
        #expect(h.editor.note.blocks[0].type == .paragraph)
    }

    @Test func urlsAndMidWordSlashesDoNotOpenTheMenu() async throws {
        let h = try await EditorHarness.make(blocks: [(.paragraph, .empty)])
        h.click(block: 0, at: 0)
        await h.type("https://apple.com and 1/2")
        #expect(h.editor.slashMenu == nil)
        #expect(h.plainBlocks == ["https://apple.com and 1/2"])
    }

    @Test func slashCommandIsOneUndoStep() async throws {
        let h = try await EditorHarness.make(blocks: [(.paragraph, RichText(plain: "Task"))])
        h.click(block: 0, at: 4)
        await h.type(" /checkbox ")
        #expect(h.editor.note.blocks[0].type == .checklistItem)
        #expect(h.plainBlocks == ["Task "])
        h.focused?.undo(nil); await h.pump()
        #expect(h.editor.note.blocks[0].type == .paragraph)
        #expect(h.plainBlocks == ["Task /checkbox "])
    }

    // MARK: Multi-block selection

    /// Runs the text view's own drag loop with synthesized mouse events.
    private func drag(_ h: EditorHarness, from start: (block: Int, offset: Int), to end: (block: Int, offset: Int)) {
        func point(_ block: Int, _ offset: Int) -> NSPoint {
            let view = h.textViews[block]
            let glyphs = view.layoutManager!.glyphRange(forCharacterRange: NSRange(location: offset, length: 0), actualCharacterRange: nil)
            var rect = view.layoutManager!.boundingRect(forGlyphRange: NSRange(location: glyphs.location, length: 0), in: view.textContainer!)
            rect.size.height = max(rect.height, 10)
            return view.convert(NSPoint(x: rect.minX + 0.5, y: rect.midY), to: nil)
        }
        func mouse(_ type: NSEvent.EventType, _ location: NSPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: 0, windowNumber: h.window.windowNumber,
                               context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        let view = h.textViews[start.block]
        var queue = [mouse(.leftMouseDragged, point(end.block, end.offset)), mouse(.leftMouseUp, point(end.block, end.offset))]
        view.trackingEvents = { _ in queue.isEmpty ? nil : queue.removeFirst() }
        view.mouseDown(with: mouse(.leftMouseDown, point(start.block, start.offset)))
    }

    @Test func dragSelectsAcrossBlocksAndBackspaceDeletesIt() async throws {
        let h = try await EditorHarness.make(blocks: [
            (.paragraph, RichText(plain: "Hello")), (.bulletItem, RichText(plain: "middle")), (.checklistItem, RichText(plain: "Task done")),
        ])
        drag(h, from: (0, 2), to: (2, 5))
        let selection = try #require(h.editor.rangeSelection)
        #expect(selection.anchor == BlockPosition(blockID: h.editor.note.blocks[0].id, offset: 2))
        #expect(h.editor.rangeSegments.map(\.range) == [2..<5, 0..<6, 0..<5])
        // The middle block is painted as selected.
        let middle = h.textViews[1]
        #expect(middle.layoutManager?.temporaryAttribute(.backgroundColor, atCharacterIndex: 0, effectiveRange: nil) != nil)

        await h.pressBackspace()
        #expect(h.plainBlocks == ["Hedone"])
        #expect(h.textViews.allSatisfy { $0.layoutManager?.temporaryAttribute(.backgroundColor, atCharacterIndex: 0, effectiveRange: nil) == nil })
    }

    @Test func dragWithinOneBlockIsANormalSelection() async throws {
        let h = try await EditorHarness.make(blocks: [(.paragraph, RichText(plain: "Hello world")), (.paragraph, RichText(plain: "next"))])
        drag(h, from: (0, 0), to: (0, 5))
        #expect(h.editor.rangeSelection == nil)
        #expect(h.textViews[0].selectedRange() == NSRange(location: 0, length: 5))
    }

    /// Regression: in a two-column note, a drag in the right column matched the
    /// left column's rows at the same height first and selected across both.
    @Test func dragInOneColumnSelectsOnlyThatColumn() async throws {
        let h = try await EditorHarness.make(blocks: ["Left one", "Left two", "Left three", "Right one", "Right two", "Right three"]
            .map { (.paragraph, RichText(plain: $0)) })
        let right = h.editor.note.blocks.suffix(3).map(\.id)
        h.editor.moveBlocks(right, toColumn: 1)
        await h.pump()
        #expect(h.editor.note.blocks.map(\.column) == [0, 0, 0, 1, 1, 1])

        drag(h, from: (3, 0), to: (4, 5))
        #expect(h.editor.rangeSegments.map(\.blockID) == [right[0], right[1]])
        #expect(h.editor.rangeSegments.map(\.range) == [0..<9, 0..<5])

        // Past the column's last row: its end, still without the left column.
        drag(h, from: (4, 0), to: (0, 2))
        #expect(h.editor.rangeSegments.map(\.blockID) == [right[0], right[1]])
    }

    /// ⌘C/⌘X go through the Edit menu, which asks the text view first. The view
    /// holding a multi-block selection has an empty selection of its own, so
    /// NSTextView alone would disable Copy and the shortcut did nothing.
    @Test func copyAndCutMenusAreEnabledForAMultiBlockSelection() async throws {
        let h = try await EditorHarness.make(blocks: [(.paragraph, RichText(plain: "One")), (.paragraph, RichText(plain: "Two"))])
        drag(h, from: (0, 0), to: (1, 3))
        let view = try #require(h.focused)
        #expect(view.selectedRange().length == 0)
        for action in [#selector(NSText.copy(_:)), #selector(NSText.cut(_:)), #selector(NSText.delete(_:))] {
            let item = NSMenuItem(title: "", action: action, keyEquivalent: "")
            #expect(view.validateUserInterfaceItem(item), "\(action) disabled")
        }
        let board = NSPasteboard(name: .init("SmartNotesTests-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        h.textViews.forEach { $0.pasteboard = board }
        #expect(NSApp.sendAction(#selector(NSText.copy(_:)), to: view, from: nil))
        #expect(board.string(forType: .string) == "One\nTwo")
    }

    @Test func copyingAMultiBlockSelectionPastesBackAsBlocks() async throws {
        let h = try await EditorHarness.make(blocks: [
            (.paragraph, RichText(plain: "Intro")), (.checklistItem, RichText(plain: "Task")), (.paragraph, RichText(plain: "")),
        ])
        let board = NSPasteboard(name: .init("SmartNotesTests-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        h.textViews.forEach { $0.pasteboard = board }
        drag(h, from: (0, 0), to: (1, 4))
        h.focused?.copy(nil)
        #expect(board.string(forType: .string) == "Intro\n- [ ] Task")
        h.click(block: 2, at: 0)
        await h.pump()
        h.focused?.paste(nil)
        await h.pump()
        #expect(h.plainBlocks == ["Intro", "Task", "Intro", "Task"])
        #expect(h.editor.note.blocks[3].type == .checklistItem)
    }

    @Test func secondSelectAllSelectsTheWholeNote() async throws {
        let h = try await EditorHarness.make(blocks: [(.paragraph, RichText(plain: "One")), (.paragraph, RichText(plain: "Two"))])
        h.click(block: 0, at: 0)
        h.focused?.selectAll(nil)
        #expect(h.editor.rangeSelection == nil)
        h.focused?.selectAll(nil)
        #expect(h.editor.rangeSegments.map(\.range) == [0..<3, 0..<3])
    }
}

/// Regression: the tag control's anchor lost its view when SwiftUI rebuilt the
/// row, so clicking a tag silently did nothing.
@MainActor
@Suite(.serialized) struct TagControlHostingTests {
    private func clickRight(of view: NSView, in window: NSWindow, by dx: CGFloat) async {
        let frame = view.convert(view.bounds, to: nil)
        let point = NSPoint(x: frame.maxX + dx, y: frame.midY)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            window.sendEvent(event)
            try? await Task.sleep(for: .milliseconds(50))
        }
        try? await Task.sleep(for: .milliseconds(200))
    }

    @Test func clickingATagOpensThePickerAfterTheRowChanges() async throws {
        let h = try await EditorHarness.make(blocks: [(.bulletItem, RichText(plain: "Milk")), (.bulletItem, RichText(plain: "Eggs"))])
        h.window.makeKeyAndOrderFront(nil)
        h.editor.setBlockTag(.priority(.high), blockID: h.editor.note.blocks[0].id)
        await h.pump()
        // The picker opens asynchronously, and under a busy full test run the
        // row can still be settling (the badge just appeared) when the click is
        // aimed: a missed click is retried. A broken anchor never opens it.
        for _ in 0..<3 where h.window.childWindows?.isEmpty ?? true {
            await clickRight(of: h.textViews[0], in: h.window, by: 22)
            for _ in 0..<10 where h.window.childWindows?.isEmpty ?? true {
                try await Task.sleep(for: .milliseconds(100))
            }
        }
        #expect(h.window.childWindows?.count == 1)
    }
}

@MainActor
@Suite(.serialized) struct NestedTextHostingTests {
    @Test func writingNestedTextKeepsReturnInsideIt() async throws {
        let h = try await EditorHarness.make(blocks: [(.checklistItem, RichText(plain: "Email marketing")), (.paragraph, RichText(plain: "next"))])
        let id = h.editor.note.blocks[0].id
        h.click(block: 0, at: 5)
        h.editor.updateSelection(blockID: id, range: 5..<5)
        h.editor.toggleNestedText()
        await h.pump()
        #expect(h.nestedTextViews.count == 1)
        #expect(h.focused === h.nestedTextViews.first)

        await h.type("Hi")
        await h.pressReturn()
        await h.type("Bye")
        #expect(h.editor.note.blocks[0].detail.plainText == "Hi\nBye")
        #expect(h.plainBlocks == ["Email marketing", "next"]) // no new block

        // ↑ from the first line goes back to the block; ↓ from the block comes back in.
        h.nestedTextViews[0].setSelectedRange(NSRange(location: 1, length: 0))
        await h.pressUp()
        #expect(h.focused === h.textViews[0])
        await h.pressDown()
        #expect(h.focused === h.nestedTextViews.first)

        // Hiding keeps the text; it is saved with the note.
        h.editor.toggleDetail(id)
        await h.pump()
        #expect(h.nestedTextViews.isEmpty)
        h.editor.flush()
        #expect(try h.deps.notes.note(id: h.editor.note.id)?.blocks[0].detail.plainText == "Hi\nBye")
    }

    @Test func backspaceInEmptyNestedTextClosesIt() async throws {
        let h = try await EditorHarness.make(blocks: [(.paragraph, RichText(plain: "Line"))])
        let id = h.editor.note.blocks[0].id
        h.editor.toggleDetail(id)
        await h.pump()
        #expect(h.focused === h.nestedTextViews.first)
        await h.pressBackspace()
        #expect(h.nestedTextViews.isEmpty)
        #expect(h.focused === h.textViews[0])
        #expect(h.plainBlocks == ["Line"])
    }

    @Test func pastingMarkdownIntoNestedTextStaysNested() async throws {
        let h = try await EditorHarness.make(blocks: [(.paragraph, RichText(plain: "Email"))])
        let id = h.editor.note.blocks[0].id
        let board = NSPasteboard(name: .init("SmartNotesTests-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        board.clearContents()
        board.setString("Ciao **team**,\n\n- punto uno\n- punto due", forType: .string)
        h.editor.toggleDetail(id)
        await h.pump()
        h.nestedTextViews[0].pasteboard = board
        h.focused?.paste(nil)
        await h.pump()
        #expect(h.plainBlocks == ["Email"])
        let detail = h.editor.note.blocks[0].detail
        #expect(detail.plainText == "Ciao team,\n\n• punto uno\n• punto due")
        #expect(detail.runs.contains(TextRun("team", marks: [.bold])))
        h.focused?.undo(nil); await h.pump()
        #expect(h.editor.note.blocks[0].detail.isEmpty)
    }

    @Test func slashNestedOpensNestedText() async throws {
        let h = try await EditorHarness.make(blocks: [(.paragraph, RichText(plain: "Task "))])
        h.click(block: 0, at: 5)
        await h.type("/nested ")
        #expect(h.plainBlocks == ["Task "])
        #expect(h.focused === h.nestedTextViews.first)
    }

    /// Each nested row's grip sits beside its first line, so the text view
    /// reports where those lines are, and again when rows change.
    @Test func nestedTextReportsWhereItsRowsStart() async throws {
        let h = try await EditorHarness.make(blocks: [(.paragraph, RichText(plain: "Email"))])
        let id = h.editor.note.blocks[0].id
        h.editor.setDetail(RichText(plain: "Ciao\n\n• Saluti\n    a tutti"), ofBlock: id)
        h.editor.toggleDetail(id)
        await h.pump()
        let view = try #require(h.nestedTextViews.first)
        #expect(view.onRowFrames != nil)
        #expect(h.textViews.allSatisfy { $0.onRowFrames == nil }) // block text has no rows
        let frames = view.rowFrames()
        #expect(frames.map(\.range) == [0..<4, 6..<26])
        #expect(frames.count == 2 && frames[0].frame.height > 0 && frames[1].frame.minY > frames[0].frame.maxY)
    }
}

/// Holds each title until the test answers, to see the link before and after.
private actor HeldLinkTitles: LinkTitleFetching {
    private var waiting: [CheckedContinuation<String?, Never>] = []
    private(set) var asked: [URL] = []

    func title(for url: URL) async -> String? {
        asked.append(url)
        return await withCheckedContinuation { waiting.append($0) }
    }

    func answer(_ title: String?) {
        waiting.forEach { $0.resume(returning: title) }
        waiting = []
    }
}

/// A drag from another app, as AppKit hands it to a drop target.
@MainActor
private final class FakeDrag: NSObject, @MainActor NSDraggingInfo {
    let draggingPasteboard: NSPasteboard
    let draggingLocation: NSPoint
    let draggingDestinationWindow: NSWindow?
    init(pasteboard: NSPasteboard, location: NSPoint, window: NSWindow?) {
        draggingPasteboard = pasteboard
        draggingLocation = location
        draggingDestinationWindow = window
    }
    var draggingSourceOperationMask: NSDragOperation { .copy }
    var draggedImageLocation: NSPoint { draggingLocation }
    var draggedImage: NSImage? { nil }
    var draggingSource: Any? { nil }
    var draggingSequenceNumber: Int { 1 }
    func slideDraggedImage(to screenPoint: NSPoint) {}
    var draggingFormation: NSDraggingFormation = .default
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions = [], for view: NSView?, classes classArray: [AnyClass],
                                searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [:], using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }
    func resetSpringLoading() {}
}

@MainActor
@Suite struct LinkPasteTests {
    private func waitUntil(_ h: EditorHarness, _ condition: () async -> Bool) async {
        for _ in 0..<500 where !(await condition()) { try? await Task.sleep(for: .milliseconds(10)) }
        await h.pump()
    }

    @Test func aPastedAddressShowsANameThenThePageTitle() async throws {
        let h = try await EditorHarness.make(blocks: [(.paragraph, RichText(plain: "see "))])
        let titles = HeldLinkTitles()
        h.editor.linkTitles = titles
        let board = NSPasteboard(name: .init("SmartNotesTests-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        board.clearContents()
        board.setString("https://example.com/release-notes", forType: .string)
        h.textViews.forEach { $0.pasteboard = board }
        h.click(block: 0, at: 4)
        h.focused?.paste(nil)
        await waitUntil(h) { await titles.asked.count == 1 }
        let link = URL(string: "https://example.com/release-notes")!
        #expect(h.editor.note.blocks[0].content.runs == [TextRun("see "), TextRun("example.com › release notes", link: link)])
        #expect(await titles.asked == [link])

        await titles.answer("Release Notes 2.0")
        await waitUntil(h) { h.plainBlocks == ["see Release Notes 2.0"] }
        #expect(h.editor.note.blocks[0].content.runs == [TextRun("see "), TextRun("Release Notes 2.0", link: link)])
        // The caret is still right after the link, so typing goes on from there.
        #expect(h.focused?.selectedRange() == NSRange(location: "see Release Notes 2.0".utf16.count, length: 0))
        await h.type("!")
        #expect(h.plainBlocks == ["see Release Notes 2.0!"])

        h.focused?.undo(nil); await h.pump()
        h.focused?.undo(nil); await h.pump()
        #expect(h.plainBlocks == ["see "])
    }

    @Test func aRenamedLinkIsLeftAlone() async throws {
        let h = try await EditorHarness.make(blocks: [(.paragraph, RichText(plain: ""))])
        let titles = HeldLinkTitles()
        h.editor.linkTitles = titles
        let board = NSPasteboard(name: .init("SmartNotesTests-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        board.clearContents()
        board.setString("https://example.com/notes", forType: .string)
        h.textViews.forEach { $0.pasteboard = board }
        h.click(block: 0, at: 0)
        h.focused?.paste(nil)
        await waitUntil(h) { await titles.asked.count == 1 }
        // The user retypes the link's text before the title arrives.
        h.select(block: 0, range: 0..<"example.com › notes".utf16.count)
        await h.type("mine")
        await titles.answer("Notes")
        try await Task.sleep(for: .milliseconds(50))
        await h.pump()
        #expect(h.plainBlocks == ["mine"])
    }

    @Test func aLinkDroppedFromABrowserIsNamed() async throws {
        let h = try await EditorHarness.make(blocks: [(.paragraph, RichText(plain: "ab"))])
        let board = NSPasteboard(name: .init("SmartNotesTests-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        board.clearContents()
        board.declareTypes([.string, .html], owner: nil)
        board.setString("https://example.com/notes", forType: .string)
        board.setString("<a href=\"https://example.com/notes\">Release notes</a>", forType: .html)
        let target = h.textViews[0]
        // At the end of the text: right of "ab".
        let location = target.convert(NSPoint(x: target.bounds.maxX - 2, y: target.bounds.midY), to: nil)
        #expect(target.performDragOperation(FakeDrag(pasteboard: board, location: location, window: h.window)))
        await h.pump()
        #expect(h.editor.note.blocks[0].content.runs
                == [TextRun("ab"), TextRun("Release notes", link: URL(string: "https://example.com/notes")!)])
    }
}

import AppKit
import SwiftUI
import Testing
@testable import SmartNotesKit

/// Regression: dragging a note in the list did nothing (the row's Button kept
/// the system drag from starting). Drives the real view with mouse events.
@MainActor
@Suite(.serialized) struct NoteListDragTests {
    private func send(_ type: NSEvent.EventType, at point: NSPoint, in window: NSWindow) async {
        let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                       windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        window.sendEvent(event)
        try? await Task.sleep(for: .milliseconds(30))
    }

    @Test func draggingANoteDownReordersTheList() async throws {
        let deps = try AppDependencies.inMemory(seedSampleData: true)
        let model = NotesModel(repository: deps.notes, settings: deps.settings, autosaveDelay: .seconds(60))
        model.load()
        model.sortMode = .title       // not Manual: the drag must still work
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 340, height: 900), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = NSHostingView(rootView: NotesListView(model: model).frame(width: 340, height: 900))
        window.makeKeyAndOrderFront(nil)
        try? await Task.sleep(for: .milliseconds(300))

        // Map rows to window heights by clicking down the list (a click selects).
        let x: CGFloat = 120
        var centers: [UUID: [CGFloat]] = [:]
        for y in stride(from: CGFloat(880), through: 20, by: -16) {
            await send(.leftMouseDown, at: NSPoint(x: x, y: y), in: window)
            await send(.leftMouseUp, at: NSPoint(x: x, y: y), in: window)
            if let id = model.selectedNoteID { centers[id, default: []].append(y) }
        }
        let others = model.groups.others.map(\.id)
        let rowY = others.compactMap { id in centers[id].map { $0.reduce(0, +) / CGFloat($0.count) } }
        try #require(rowY.count == others.count && others.count >= 3, "found \(rowY.count) of \(others.count) rows")

        // Drag the first unpinned note to just below the third one.
        let start = NSPoint(x: x, y: rowY[0])
        let end = NSPoint(x: x, y: rowY[2] - 20)   // window y grows upward
        await send(.leftMouseDown, at: start, in: window)
        for step in 1...12 {
            let t = CGFloat(step) / 12
            await send(.leftMouseDragged, at: NSPoint(x: x, y: start.y + (end.y - start.y) * t), in: window)
        }
        await send(.leftMouseUp, at: end, in: window)
        try? await Task.sleep(for: .milliseconds(200))

        #expect(model.sortMode == .manual)
        #expect(model.groups.others.map(\.id) == [others[1], others[2], others[0]] + others.dropFirst(3))
    }
}

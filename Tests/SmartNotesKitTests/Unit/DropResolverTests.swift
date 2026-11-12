import CoreGraphics
import Foundation
import Testing
@testable import SmartNotesKit

@Suite struct DropResolverTests {
    private let ids = (0..<4).map { _ in UUID() }
    // Rows 30 pt tall with 4 pt gaps: 0–30, 34–64, 68–98, 102–132.
    private var frames: [(id: UUID, frame: CGRect)] {
        ids.enumerated().map { ($1, CGRect(x: 0, y: CGFloat($0) * 34, width: 300, height: 30)) }
    }

    @Test func upperHalfIsBeforeLowerHalfIsAfter() {
        #expect(DropResolver.target(pointerY: 72, frames: frames, dragged: ids[0]) == .init(id: ids[2], placeAfter: false))
        #expect(DropResolver.target(pointerY: 95, frames: frames, dragged: ids[0]) == .init(id: ids[2], placeAfter: true))
    }

    @Test func beyondTheEnds() {
        #expect(DropResolver.target(pointerY: -40, frames: frames, dragged: ids[3]) == .init(id: ids[0], placeAfter: false))
        #expect(DropResolver.target(pointerY: 500, frames: frames, dragged: ids[0]) == .init(id: ids[3], placeAfter: true))
    }

    @Test func gapsSnapToTheNearestRow() {
        // Midway between rows 1 and 2: "after 1" and "before 2" are the same slot.
        let slot = DropResolver.target(pointerY: 66, frames: frames, dragged: ids[0])
        #expect(slot == .init(id: ids[1], placeAfter: true) || slot == .init(id: ids[2], placeAfter: false))
    }

    @Test func droppingNextToItselfIsNotAMove() {
        // Dragging row 1 onto the lower half of row 0 or the upper half of row 2: same place.
        #expect(DropResolver.target(pointerY: 25, frames: frames, dragged: ids[1]) == nil)
        #expect(DropResolver.target(pointerY: 70, frames: frames, dragged: ids[1]) == nil)
        // Hovering over its own (vacated) position is not a move either.
        #expect(DropResolver.target(pointerY: 40, frames: frames, dragged: ids[1]) == nil)
    }

    @Test func singleRowHasNowhereToGo() {
        #expect(DropResolver.target(pointerY: 10, frames: Array(frames.prefix(1)), dragged: ids[0]) == nil)
    }

    @Test func previewSlidesTheRowsBetweenOldAndNewPlace() {
        let ids = (0..<5).map { _ in UUID() }
        func offsets(_ target: DropResolver.Target?) -> [CGFloat] {
            ids.map { DropResolver.previewOffset(of: $0, order: ids, dragged: ids[1], target: target, gap: 30) }
        }
        // Down: after row 3 → rows 2 and 3 move up into the gap.
        #expect(DropResolver.finalIndex(order: ids, dragged: ids[1], target: .init(id: ids[3], placeAfter: true)) == 3)
        #expect(offsets(.init(id: ids[3], placeAfter: true)) == [0, 0, -30, -30, 0])
        // Up: before row 0 → row 0 moves down.
        #expect(offsets(.init(id: ids[0], placeAfter: false)) == [30, 0, 0, 0, 0])
        // No target (dropping where it is): nothing moves.
        #expect(offsets(nil) == [0, 0, 0, 0, 0])
    }
}

@Suite struct NestDropTests {
    private let ids = (0..<3).map { _ in UUID() }
    // Rows 30 pt tall with 4 pt gaps: 0–30, 34–64, 68–98.
    private var frames: [(id: UUID, frame: CGRect)] {
        ids.enumerated().map { ($1, CGRect(x: 0, y: CGFloat($0) * 34, width: 300, height: 30)) }
    }

    @Test func middleOfAnotherRowNests() {
        #expect(DropResolver.nestTarget(pointerY: 49, frames: frames, dragged: ids[0]) == ids[1])
        #expect(DropResolver.nestTarget(pointerY: 83, frames: frames, dragged: ids[0]) == ids[2])
    }

    @Test func edgesGapsAndItselfDoNotNest() {
        #expect(DropResolver.nestTarget(pointerY: 36, frames: frames, dragged: ids[0]) == nil) // top edge of row 1
        #expect(DropResolver.nestTarget(pointerY: 62, frames: frames, dragged: ids[0]) == nil) // bottom edge
        #expect(DropResolver.nestTarget(pointerY: 66, frames: frames, dragged: ids[0]) == nil) // gap
        #expect(DropResolver.nestTarget(pointerY: 15, frames: frames, dragged: ids[0]) == nil) // its own row
    }

    @Test func tallRowsKeepNarrowReorderEdges() {
        let tall = [(id: ids[0], frame: CGRect(x: 0, y: 0, width: 300, height: 200))]
        #expect(DropResolver.nestTarget(pointerY: 12, frames: tall, dragged: ids[1]) == ids[0])
        #expect(DropResolver.nestTarget(pointerY: 8, frames: tall, dragged: ids[1]) == nil)
    }

    /// A nested row dragged out is not one of the rows, so every gap is a change.
    @Test func insertionAcceptsEveryGap() {
        #expect(DropResolver.insertion(pointerY: -5, frames: frames) == .init(id: ids[0], placeAfter: false))
        #expect(DropResolver.insertion(pointerY: 32, frames: frames) == .init(id: ids[0], placeAfter: true))
        #expect(DropResolver.insertion(pointerY: 36, frames: frames) == .init(id: ids[1], placeAfter: false))
        #expect(DropResolver.insertion(pointerY: 120, frames: frames) == .init(id: ids[2], placeAfter: true))
        #expect(DropResolver.insertion(pointerY: 10, frames: []) == nil)
    }
}

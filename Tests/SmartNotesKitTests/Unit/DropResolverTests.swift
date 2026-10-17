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
}

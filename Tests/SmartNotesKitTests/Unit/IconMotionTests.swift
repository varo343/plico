import Testing
@testable import SmartNotesKit

@Suite struct IconMotionTests {
    private let symbols = [
        "trash", "trash.fill", "xmark.bin", "trash.slash", "xmark", "xmark.circle", "pin", "pin.fill", "pin.slash", "tag", "tag.slash",
        "flag", "flag.checkered", "exclamationmark", "exclamationmark.2", "exclamationmark.3", "exclamationmark.triangle",
        "calendar", "calendar.badge.clock", "sun.max", "sun.max.fill", "sunrise", "clock.arrow.circlepath", "arrow.clockwise",
        "gearshape", "arrow.up.arrow.down", "arrow.uturn.backward", "envelope", "envelope.open", "square.and.arrow.up", "tray",
        "at", "externaldrive", "square.and.pencil", "plus.square.on.square", "sparkles", "hand.draw", "magnifyingglass",
        "bold", "italic", "underline", "strikethrough", "chevron.left.forwardslash.chevron.right", "ellipsis", "link",
        "textformat", "textformat.size", "textformat.size.larger", "textformat.size.smaller", "character", "text.quote",
        "checklist", "list.bullet", "list.number", "text.alignleft", "note.text", "sidebar.left", "something.unknown",
    ]

    /// Angles may finish on a whole symmetric turn (sun, gear, refresh) because the
    /// last keyframe snaps back to 0; everything else must land exactly at rest.
    @Test func everyMotionEndsAtRestAndStaysShort() {
        for symbol in symbols {
            let m = IconMotion.forSymbol(symbol)
            for (track, rest) in [(m.angle, 0.0), (m.x, 0), (m.y, 0), (m.scale, 1), (m.scaleX, 1), (m.scaleY, 1)] where !track.isEmpty {
                #expect(track.last?.value == rest, "\(symbol) does not return to rest")
                #expect(track.map(\.duration).reduce(0, +) <= 0.6, "\(symbol) is too long")
            }
        }
    }

    @Test func calendarHasNoTurn() {
        let calendar = IconMotion.forSymbol("calendar")
        #expect(calendar.angle.isEmpty && calendar.x.isEmpty)
    }
}

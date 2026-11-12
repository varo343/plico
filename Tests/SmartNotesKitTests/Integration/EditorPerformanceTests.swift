import AppKit
import Testing
@testable import SmartNotesKit

/// Guards against the editor's costs growing with the square of its rows.
@MainActor
@Suite(.serialized) struct EditorPerformanceTests {
    /// A plain NSTextView with a superview hears every view's frame change
    /// (in any window, or none: SwiftUI builds rows before adding them); with
    /// one per row, each layout pass cost rows × views. Block text views opt
    /// out, so a frame change costs about the same with 150 rows.
    @Test func rowTextViewsDoNotHearEveryFrameChange() {
        func costOfFrameChanges(with makeView: () -> NSView) -> Duration { autoreleasepool {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            defer { window.close() }
            let other = NSView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
            window.contentView!.addSubview(other)
            let hosts = (0..<150).map { _ in
                let host = NSView(frame: NSRect(x: 0, y: 20, width: 200, height: 20))
                host.addSubview(makeView())
                return host
            }
            let clock = ContinuousClock()
            let start = clock.now
            for i in 0..<3000 { other.setFrameSize(NSSize(width: 10 + i % 2, height: 10)) }
            withExtendedLifetime(hosts) {}
            return clock.now - start
        } }
        // Each in its own pool, so one run's views are gone before the next.
        let plain = costOfFrameChanges { NSView() }
        let rows = costOfFrameChanges { BlockNSTextView() }
        let textViews = costOfFrameChanges { NSTextView() }
        // NSTextView costs over ten times plain views here; rows stay close to plain.
        #expect(rows < plain * 4 + .milliseconds(5), "rows \(rows), plain views \(plain), NSTextView \(textViews)")
    }

    @Test func rowFramesFreezeDuringADrag() {
        let geometry = EditorGeometry()
        let id = UUID()
        geometry.liveFrames[id] = CGRect(x: 0, y: 10, width: 100, height: 20)
        geometry.freeze()
        // While dragging, rows are offset: the frames used stay where the rows are.
        geometry.liveFrames[id] = CGRect(x: 0, y: 60, width: 100, height: 20)
        #expect(geometry.blockFrames[id]?.minY == 10)
        geometry.thaw()
        #expect(geometry.blockFrames[id]?.minY == 60)
    }
}

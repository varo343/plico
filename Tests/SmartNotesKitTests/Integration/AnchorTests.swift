import AppKit
import SwiftUI
import Testing
@testable import SmartNotesKit

@MainActor
@Suite struct AnchorTests {
    /// Regression: dropdowns opened far from their button when the control lived
    /// in a hosting view that isn't the window's content view (e.g. a column).
    @Test func anchorMatchesControlInsideOffsetHostingView() async throws {
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        window.contentView = container

        let box = AnchorBox()
        let column = NSHostingView(rootView:
            Color.clear.frame(width: 50, height: 20)
                .background(AnchorReader(box: box))
                .padding(.leading, 30).padding(.top, 30)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        )
        column.frame = NSRect(x: 200, y: 0, width: 400, height: 400) // a "second column"
        container.addSubview(column)
        // Wait for layout (the suite runs in parallel, so no fixed delay).
        let deadline = ContinuousClock.now + .seconds(5)
        while (box.screenRect?.width ?? 0) < 1, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }

        let expected = window.convertToScreen(NSRect(x: 200 + 30, y: 400 - 30 - 20, width: 50, height: 20))
        let actual = try #require(box.screenRect)
        #expect(abs(actual.minX - expected.minX) < 1 && abs(actual.minY - expected.minY) < 1)
        #expect(abs(actual.width - 50) < 1 && abs(actual.height - 20) < 1)
    }
}

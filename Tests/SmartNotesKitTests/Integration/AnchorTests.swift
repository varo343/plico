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

@MainActor
@Suite(.serialized) struct FloatingPanelPlacementTests {
    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.orderFront(nil)
        return window
    }

    @Test func tooltipIsCenteredBelowItsControl() {
        let window = makeWindow()
        defer { window.close() }
        let anchor = window.convertToScreen(NSRect(x: 100, y: 300, width: 40, height: 20))
        let controller = FloatingPanelController()
        controller.show(Text("Tooltip text").padding(6), below: anchor, in: window, acceptsKey: false,
                        centered: true, passesClicksThrough: true)
        defer { controller.close() }
        let frame = controller.panelFrame
        #expect(frame != nil)
        #expect(abs((frame?.midX ?? 0) - anchor.midX) < 1)
        #expect((frame?.maxY ?? .infinity) <= anchor.minY + FloatingPanelController.margin) // below, content top under the control
    }

    @Test func tooltipCanOpenAbove() {
        let window = makeWindow()
        defer { window.close() }
        let anchor = window.convertToScreen(NSRect(x: 100, y: 100, width: 40, height: 20))
        let controller = FloatingPanelController()
        controller.show(Text("Above").padding(6), below: anchor, in: window, acceptsKey: false,
                        centered: true, preferAbove: true, passesClicksThrough: true)
        defer { controller.close() }
        #expect((controller.panelFrame?.minY ?? 0) >= anchor.maxY - FloatingPanelController.margin)
    }

    @Test func menuAlignsWithLeadingEdgeOfItsButton() {
        let window = makeWindow()
        defer { window.close() }
        let anchor = window.convertToScreen(NSRect(x: 300, y: 300, width: 30, height: 24))
        let controller = FloatingPanelController()
        controller.show(SNMenuList(entries: [.item(SNMenuItem(title: "A") {})], dismiss: {}), below: anchor, in: window, acceptsKey: true)
        defer { controller.close() }
        #expect(abs(((controller.panelFrame?.minX ?? 0) + FloatingPanelController.margin) - anchor.minX) < 1)
        #expect((controller.panelFrame?.maxY ?? .infinity) <= anchor.minY + FloatingPanelController.margin)
    }
}

import AppKit
import SwiftUI
import Testing
@testable import SmartNotesKit

/// Regression: hovering a section expands the switcher; at the old minimum
/// width the header overflowed the list column onto its margins.
@MainActor
@Suite struct ListColumnLayoutTests {
    private func width<V: View>(_ view: V) -> CGFloat { NSHostingView(rootView: view).fittingSize.width }

    @Test func headerFitsAtMinimumColumnWidthWhileHovering() throws {
        let app = AppModel(dependencies: try AppDependencies.inMemory())
        let widestSwitcher = SidebarDestination.allCases
            .map { width(SectionSwitcher(selection: .constant(.notes), hovered: $0)) }
            .max() ?? 0
        let widestAccessory = max(width(NotesSortMenu(model: app.notes)), width(MentionsHeaderControls(outlook: app.outlook)))
        // RootView's header: horizontal padding `m` on both sides, spacing `xs`.
        let needed = widestSwitcher + SNSpacing.xs + widestAccessory + SNSpacing.m * 2
        #expect(needed <= ColumnResizeHandle.minWidth, "header needs \(needed) pt")
    }
}

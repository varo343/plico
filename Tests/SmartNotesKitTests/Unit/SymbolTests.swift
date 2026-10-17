import AppKit
import Testing
@testable import SmartNotesKit

/// Regression: a missing SF Symbol renders as nothing, silently (the drag grip
/// disappeared that way). Every symbol the UI picks from model types must exist.
@MainActor
@Suite struct SymbolTests {
    @Test func everySymbolUsedByTheUIExists() {
        var names: [String] = []
        names += SidebarDestination.allCases.flatMap { [$0.symbol, $0.selectedSymbol] }
        names += BlockType.allCases.map(\.symbol)
        names += NoteSortMode.allCases.map(\.symbol)
        names += FontFamilyPreset.allCases.map(\.symbol)
        names += OutlookImportScope.allCases.map(\.symbol)
        names += SettingsPane.allCases.map(\.symbol)
        names += ["pin", "pin.fill", "pin.slash", "trash", "xmark.bin", "plus.square.on.square", "sidebar.left", "flag",
                  "flag.checkered", "calendar", "arrow.up.arrow.down", "arrow.clockwise", "arrow.uturn.backward",
                  "square.and.pencil", "envelope", "envelope.open", "xmark.circle", "square.and.arrow.up", "link",
                  "ellipsis", "checkmark", "checkmark.square.fill", "square", "magnifyingglass", "sunrise", "calendar.badge.clock"]
        let missing = Set(names).filter { NSImage(systemSymbolName: $0, accessibilityDescription: nil) == nil }
        #expect(missing.isEmpty, "Missing SF Symbols: \(missing.sorted())")
    }
}

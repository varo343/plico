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
        names += ["pin", "pin.fill", "pin.slash", "trash", "plus.square.on.square", "sidebar.left", "flag",
                  "flag.checkered", "calendar", "arrow.up.arrow.down", "arrow.clockwise", "arrow.uturn.backward",
                  "square.and.pencil", "envelope", "envelope.open", "xmark.circle", "square.and.arrow.up", "link",
                  "ellipsis", "checkmark", "checkmark.square.fill", "square", "magnifyingglass", "sunrise", "calendar.badge.clock",
                  "tag", "tag.slash", "exclamationmark", "exclamationmark.2", "exclamationmark.3",
                  "chevron.right", "text.alignleft", "text.badge.plus",
                  "arrow.up.arrow.down", "checkmark.circle", "arrow.down.to.line", "arrow.down", "arrow.up", "circle",
                  "rectangle.split.2x1", "photo", "photo.badge.exclamationmark",
                  "plus.square.on.square", "doc.on.doc", "doc.on.clipboard", "clipboard", "scissors",
                  "rectangle.righthalf.inset.filled", "rectangle.lefthalf.inset.filled", "arrow.up.left.and.arrow.down.right",
                  "1.magnifyingglass", "rectangle.portrait.and.arrow.right", "plus.circle.fill", "arrow.up.forward.app"]
        names += SlashCommand.all.map(\.symbol)
        let missing = Set(names).filter { NSImage(systemSymbolName: $0, accessibilityDescription: nil) == nil }
        #expect(missing.isEmpty, "Missing SF Symbols: \(missing.sorted())")
    }
}

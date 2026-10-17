// swift-tools-version: 6.0
import PackageDescription

// Plico (formerly "Smart Notes") is a dependency-free SwiftPM package so it builds with the stock
// Xcode toolchain (no xcodegen/tuist). `scripts/build-app.sh` wraps the
// executable in a signed .app bundle.
let package = Package(
    name: "SmartNotes",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Plico", targets: ["SmartNotesApp"]),
    ],
    targets: [
        // Domain, persistence, integrations and feature UI. Kept as a library so
        // business rules and repositories are unit-testable.
        .target(
            name: "SmartNotesKit",
            path: "Sources/SmartNotesKit"
        ),
        // Thin @main entry point.
        .executableTarget(
            name: "SmartNotesApp",
            dependencies: ["SmartNotesKit"],
            path: "Sources/SmartNotesApp"
        ),
        // Dev tool: renders the app icon from the PlicoLogo view (scripts/make-icon.sh).
        .executableTarget(
            name: "PlicoIconGenerator",
            dependencies: ["SmartNotesKit"],
            path: "Sources/PlicoIconGenerator"
        ),
        .testTarget(
            name: "SmartNotesKitTests",
            dependencies: ["SmartNotesKit"],
            path: "Tests/SmartNotesKitTests"
        ),
    ]
)

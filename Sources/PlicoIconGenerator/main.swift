import AppKit
import SmartNotesKit
import SwiftUI

// Renders Plico's app icon at every macOS size into an .iconset folder.
// Usage: swift run PlicoIconGenerator <output.iconset>   (then: iconutil -c icns)
@MainActor
func render(pixels: Int, to url: URL) throws {
    let renderer = ImageRenderer(content: PlicoLogo(size: CGFloat(pixels), showsTile: true))
    renderer.scale = 1
    guard let image = renderer.cgImage else { throw CocoaError(.fileWriteUnknown) }
    let rep = NSBitmapImageRep(cgImage: image)
    guard let png = rep.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
    try png.write(to: url)
}

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "AppIcon.iconset")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let sizes = [16, 32, 128, 256, 512]
try MainActor.assumeIsolated {
    for size in sizes {
        try render(pixels: size, to: output.appendingPathComponent("icon_\(size)x\(size).png"))
        try render(pixels: size * 2, to: output.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
    }
}
print("Wrote \(sizes.count * 2) images to \(output.path)")

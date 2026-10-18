import SwiftUI

/// Plico's logo: a cream organic oval (the New Note button's shape) with a
/// few lines of "writing", on yellow. Deliberately simple. Fixed colors so the
/// app icon is identical in light and dark mode; geometry is relative to `size`.
public struct PlicoLogo: View {
    private let size: CGFloat
    private let showsTile: Bool

    /// - showsTile: draws the macOS app-icon tile (yellow rounded square with margin and shadow).
    ///   Without it, the logo sits on a yellow circle-ish blob of its own.
    public init(size: CGFloat, showsTile: Bool = false) {
        self.size = size
        self.showsTile = showsTile
    }

    private enum Palette {
        static let ink = Color(red: 0.12, green: 0.11, blue: 0.10)
        static let paper = Color(red: 1.0, green: 0.98, blue: 0.94)
        static let yellowTop = Color(red: 0.98, green: 0.82, blue: 0.42)
        static let yellowBottom = Color(red: 0.95, green: 0.74, blue: 0.30)
    }

    public var body: some View {
        // macOS icon grid: the tile is 824/1024 of the canvas, centered.
        let tile = showsTile ? size * 0.805 : size
        ZStack {
            Group {
                if showsTile {
                    RoundedRectangle(cornerRadius: tile * 0.225, style: .continuous)
                        .fill(LinearGradient(colors: [Palette.yellowTop, Palette.yellowBottom], startPoint: .top, endPoint: .bottom))
                        .overlay(RoundedRectangle(cornerRadius: tile * 0.225, style: .continuous).strokeBorder(.black.opacity(0.08), lineWidth: tile * 0.004))
                        .shadow(color: .black.opacity(0.22), radius: tile * 0.03, y: tile * 0.02)
                } else {
                    RoundedRectangle(cornerRadius: tile * 0.28, style: .continuous)
                        .fill(LinearGradient(colors: [Palette.yellowTop, Palette.yellowBottom], startPoint: .top, endPoint: .bottom))
                }
            }
            .frame(width: tile, height: tile)
            oval(tile)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Plico")
    }

    /// The oval with three lines of writing.
    private func oval(_ s: CGFloat) -> some View {
        let line = max(1, s * 0.03)
        let width = s * 0.62, height = s * 0.54
        return ZStack {
            OrganicBlobShape().fill(Palette.ink).offset(x: s * 0.022, y: s * 0.03)
            OrganicBlobShape().fill(Palette.paper)
            OrganicBlobShape().stroke(Palette.ink, style: StrokeStyle(lineWidth: line, lineJoin: .round))
            VStack(alignment: .leading, spacing: s * 0.055) {
                Capsule().fill(Palette.ink).frame(width: s * 0.3, height: line * 1.15)
                Capsule().fill(Palette.ink.opacity(0.5)).frame(width: s * 0.36, height: line)
                Capsule().fill(Palette.ink.opacity(0.5)).frame(width: s * 0.22, height: line)
            }
            .frame(width: s * 0.38, alignment: .leading)
        }
        .frame(width: width, height: height)
        .rotationEffect(.degrees(-4))
    }
}

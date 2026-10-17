import SwiftUI

/// Plico's logo: an envelope ("plico") holding a note, on the yellow organic
/// blob from the New Note button. Fixed colors so the app icon is identical in
/// light and dark mode. All geometry is relative to `size`.
public struct PlicoLogo: View {
    private let size: CGFloat
    private let showsTile: Bool

    /// - showsTile: draws the macOS app-icon tile (rounded square with margin and shadow).
    public init(size: CGFloat, showsTile: Bool = false) {
        self.size = size
        self.showsTile = showsTile
    }

    private enum Palette {
        static let ink = Color(red: 0.12, green: 0.11, blue: 0.10)
        static let yellow = Color(red: 0.965, green: 0.776, blue: 0.357)
        static let paper = Color(red: 1.0, green: 0.996, blue: 0.98)
        static let envelope = Color(red: 0.99, green: 0.95, blue: 0.87)
        static let tileTop = Color(red: 0.99, green: 0.97, blue: 0.92)
        static let tileBottom = Color(red: 0.94, green: 0.91, blue: 0.85)
    }

    public var body: some View {
        // Artwork inside the macOS icon grid: 824/1024 tile, centered.
        let tile = showsTile ? size * 0.805 : size
        ZStack {
            if showsTile {
                RoundedRectangle(cornerRadius: tile * 0.225, style: .continuous)
                    .fill(LinearGradient(colors: [Palette.tileTop, Palette.tileBottom], startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: tile * 0.225, style: .continuous).strokeBorder(.black.opacity(0.06), lineWidth: tile * 0.004))
                    .frame(width: tile, height: tile)
                    .shadow(color: .black.opacity(0.22), radius: tile * 0.03, y: tile * 0.02)
            }
            mark(tile * (showsTile ? 0.86 : 1))
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Plico")
    }

    private func mark(_ s: CGFloat) -> some View {
        let line = max(1, s * 0.022)
        return ZStack {
            // Blob with the hard "cartoon" offset shadow, like the New Note button.
            OrganicBlobShape().fill(Palette.ink).frame(width: s * 0.86, height: s * 0.84).offset(x: s * 0.025, y: s * 0.035)
            OrganicBlobShape().fill(Palette.yellow).frame(width: s * 0.86, height: s * 0.84)
            OrganicBlobShape().stroke(Palette.ink, style: StrokeStyle(lineWidth: line, lineJoin: .round)).frame(width: s * 0.86, height: s * 0.84)

            // The note, peeking out of the envelope.
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: s * 0.03).fill(Palette.paper)
                RoundedRectangle(cornerRadius: s * 0.03).stroke(Palette.ink, lineWidth: line)
                VStack(alignment: .leading, spacing: s * 0.035) {
                    Capsule().fill(Palette.ink).frame(width: s * 0.2, height: line * 1.1)
                    Capsule().fill(Palette.ink.opacity(0.55)).frame(width: s * 0.26, height: line * 0.9)
                    Capsule().fill(Palette.ink.opacity(0.55)).frame(width: s * 0.17, height: line * 0.9)
                }
                .padding(.top, s * 0.06)
                .padding(.leading, s * 0.055)
            }
            .frame(width: s * 0.38, height: s * 0.34)
            .rotationEffect(.degrees(-7))
            .offset(x: -s * 0.01, y: -s * 0.1)

            // The envelope's front pocket.
            ZStack {
                EnvelopeFront().fill(Palette.envelope)
                EnvelopeFront().stroke(Palette.ink, style: StrokeStyle(lineWidth: line, lineJoin: .round))
                EnvelopeFold().stroke(Palette.ink, style: StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round))
            }
            .frame(width: s * 0.5, height: s * 0.27)
            .offset(y: s * 0.11)
        }
        .frame(width: s, height: s)
    }
}

/// Envelope body: a rounded rectangle.
private struct EnvelopeFront: Shape {
    func path(in rect: CGRect) -> Path {
        Path(roundedRect: rect, cornerRadius: rect.height * 0.14)
    }
}

/// The V of the envelope's pocket, from the top corners to the middle.
private struct EnvelopeFold: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.04, y: rect.minY + rect.height * 0.08))
        path.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.6),
                          control: CGPoint(x: rect.minX + rect.width * 0.3, y: rect.minY + rect.height * 0.48))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - rect.width * 0.04, y: rect.minY + rect.height * 0.08),
                          control: CGPoint(x: rect.maxX - rect.width * 0.3, y: rect.minY + rect.height * 0.48))
        return path
    }
}

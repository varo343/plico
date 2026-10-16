import SwiftUI

// Fixed vector shapes for the cartoon accents. Paths are hand-tuned constants
// (never randomized) so the silhouette is identical on every launch.

/// Mildly asymmetric blob used for the New Note button.
public struct OrganicBlobShape: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        var path = Path()
        path.move(to: p(0.53, 0.02))
        path.addCurve(to: p(0.97, 0.46), control1: p(0.80, 0.01), control2: p(0.99, 0.20))
        path.addCurve(to: p(0.49, 0.98), control1: p(0.96, 0.76), control2: p(0.77, 1.00))
        path.addCurve(to: p(0.03, 0.53), control1: p(0.21, 0.97), control2: p(0.02, 0.81))
        path.addCurve(to: p(0.53, 0.02), control1: p(0.04, 0.24), control2: p(0.25, 0.03))
        path.closeSubpath()
        return path
    }
}

/// Subtly asymmetric pill for the selected sidebar destination.
public struct OrganicPillShape: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        let r = min(rect.height / 2, 14)
        let w = rect.width, h = rect.height, x = rect.minX, y = rect.minY
        var path = Path()
        path.move(to: CGPoint(x: x + r, y: y + 1))
        path.addCurve(to: CGPoint(x: x + w - r, y: y), control1: CGPoint(x: x + w * 0.4, y: y - 0.5), control2: CGPoint(x: x + w * 0.7, y: y + 1))
        path.addQuadCurve(to: CGPoint(x: x + w, y: y + h * 0.48), control: CGPoint(x: x + w + 0.5, y: y))
        path.addQuadCurve(to: CGPoint(x: x + w - r * 1.1, y: y + h), control: CGPoint(x: x + w, y: y + h + 0.5))
        path.addCurve(to: CGPoint(x: x + r * 0.9, y: y + h - 1), control1: CGPoint(x: x + w * 0.6, y: y + h + 0.5), control2: CGPoint(x: x + w * 0.3, y: y + h - 1))
        path.addQuadCurve(to: CGPoint(x: x, y: y + h * 0.52), control: CGPoint(x: x - 0.5, y: y + h))
        path.addQuadCurve(to: CGPoint(x: x + r, y: y + 1), control: CGPoint(x: x, y: y + 0.5))
        path.closeSubpath()
        return path
    }
}

/// Hand-drawn capsule for tags: uneven ends and slightly bowed edges.
/// `variant` picks one of a few fixed wobbles (never random).
public struct WobblyCapsuleShape: Shape {
    var variant: Int = 0
    /// Scales the irregularity (1 = subtle, 2 = clearly hand-drawn).
    var amplitude: CGFloat = 1

    public func path(in rect: CGRect) -> Path {
        // Fixed per-variant offsets (in points), small enough to stay legible.
        let wobbles: [[CGFloat]] = [
            [1.2, -0.7, 0.4, 0.9, -0.5, 0.6],
            [0.5, 0.8, -0.6, 0.3, 1.0, -0.4],
            [-0.4, 0.4, 1.0, -0.7, 0.2, 0.9],
            [0.9, -0.3, 0.6, 0.5, -0.8, 0.2],
        ]
        let w = wobbles[abs(variant) % wobbles.count].map { $0 * amplitude }
        let a = amplitude
        let minX = rect.minX, maxX = rect.maxX, minY = rect.minY, maxY = rect.maxY
        let r = rect.height / 2
        var path = Path()
        path.move(to: CGPoint(x: minX + r * 0.95, y: minY + w[0] * 0.6))
        // Top edge, gently bowed.
        path.addCurve(to: CGPoint(x: maxX - r * 1.05, y: minY + w[1] * 0.5),
                      control1: CGPoint(x: minX + rect.width * 0.35, y: minY - 0.9 * a + w[2] * 0.4),
                      control2: CGPoint(x: minX + rect.width * 0.7, y: minY + 0.5 * a + w[3] * 0.4))
        // Right end, a bit squarer than a true semicircle.
        path.addCurve(to: CGPoint(x: maxX - r * 0.9, y: maxY - 0.3 + w[4] * 0.4),
                      control1: CGPoint(x: maxX + 0.9 * a + w[3] * 0.4, y: minY + r * 0.15),
                      control2: CGPoint(x: maxX + 0.4 * a, y: maxY - r * 0.05))
        // Bottom edge.
        path.addCurve(to: CGPoint(x: minX + r * 1.1, y: maxY + w[5] * 0.5),
                      control1: CGPoint(x: minX + rect.width * 0.62, y: maxY + 0.8 * a),
                      control2: CGPoint(x: minX + rect.width * 0.3, y: maxY - 0.4 * a + w[0] * 0.3))
        // Left end.
        path.addCurve(to: CGPoint(x: minX + r * 0.95, y: minY + w[0] * 0.6),
                      control1: CGPoint(x: minX - 0.8 * a + w[1] * 0.4, y: maxY - r * 0.1),
                      control2: CGPoint(x: minX - 0.3 * a, y: minY + r * 0.1))
        path.closeSubpath()
        return path
    }
}

/// Hand-drawn rounded rectangle for icon-button hovers: slightly uneven
/// corners and edges, fixed per `variant`.
public struct WobblyRoundedRectShape: Shape {
    var radius: CGFloat
    var variant: Int = 0

    public func path(in rect: CGRect) -> Path {
        let offsets: [[CGFloat]] = [[0.8, -0.6, 0.5, -0.4], [-0.5, 0.7, -0.3, 0.6], [0.4, 0.3, -0.7, -0.5]]
        let o = offsets[abs(variant) % offsets.count]
        let r = min(radius, rect.height / 2, rect.width / 2)
        let (x0, y0, x1, y1) = (rect.minX, rect.minY, rect.maxX, rect.maxY)
        var path = Path()
        path.move(to: CGPoint(x: x0 + r, y: y0 + o[0] * 0.5))
        path.addQuadCurve(to: CGPoint(x: x1 - r, y: y0 + o[1] * 0.5), control: CGPoint(x: rect.midX, y: y0 - 0.8 + o[2] * 0.4))
        path.addQuadCurve(to: CGPoint(x: x1 + o[3] * 0.4, y: y0 + r), control: CGPoint(x: x1 + 0.3, y: y0 - 0.2))
        path.addQuadCurve(to: CGPoint(x: x1 + o[0] * 0.4, y: y1 - r), control: CGPoint(x: x1 + 0.9, y: rect.midY + o[1]))
        path.addQuadCurve(to: CGPoint(x: x1 - r, y: y1 + o[2] * 0.4), control: CGPoint(x: x1 + 0.2, y: y1 + 0.3))
        path.addQuadCurve(to: CGPoint(x: x0 + r, y: y1 + o[3] * 0.5), control: CGPoint(x: rect.midX, y: y1 + 0.9 + o[0] * 0.3))
        path.addQuadCurve(to: CGPoint(x: x0 + o[1] * 0.4, y: y1 - r), control: CGPoint(x: x0 - 0.3, y: y1 + 0.2))
        path.addQuadCurve(to: CGPoint(x: x0 + o[2] * 0.4, y: y0 + r), control: CGPoint(x: x0 - 0.9, y: rect.midY + o[3]))
        path.addQuadCurve(to: CGPoint(x: x0 + r, y: y0 + o[0] * 0.5), control: CGPoint(x: x0 - 0.2, y: y0 - 0.3))
        path.closeSubpath()
        return path
    }
}

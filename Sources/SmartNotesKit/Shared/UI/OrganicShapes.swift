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

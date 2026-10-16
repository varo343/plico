import AppKit
import SwiftUI

/// Semantic design tokens from the UX/UI spec §4. Views use these, never raw hex.
public enum SNColor {
    public static let canvas = dynamic(light: 0xF8F5ED, dark: 0x211F1C)
    public static let sidebar = dynamic(light: 0xF0ECE3, dark: 0x292622)
    public static let card = dynamic(light: 0xFFFEFA, dark: 0x302C28)
    public static let textPrimary = dynamic(light: 0x292929, dark: 0xF5F1E9)
    public static let textSecondary = dynamic(light: 0x77736C, dark: 0xB5ADA3)
    public static let borderSubtle = dynamic(light: 0xDED8CE, dark: 0x48413A)
    public static let accentYellow = dynamic(light: 0xF6C65B, dark: 0xF6C65B)
    public static let accentMint = dynamic(light: 0xD5E9D3, dark: 0x3A5645)
    public static let accentCoral = dynamic(light: 0xF4B9A8, dark: 0x6A4038)
    /// Soft, opaque yellow for badges (the strong yellow stays reserved for the FAB).
    public static let accentSun = dynamic(light: 0xFBE4AA, dark: 0x5F4B1F)
    public static let focusRing = dynamic(light: 0x755B21, dark: 0xF6D780)
    /// Near-black ink for outlines/icons on the yellow accent (both themes).
    public static let ink = dynamic(light: 0x1F1D1A, dark: 0x1F1D1A)
    /// Cartoon outline on neutral surfaces: ink in light mode, warm off-white in dark.
    public static let outline = dynamic(light: 0x1F1D1A, dark: 0xE9E2D6)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

public enum SNSpacing {
    public static let xxs: CGFloat = 4
    public static let xs: CGFloat = 8
    public static let s: CGFloat = 12
    public static let m: CGFloat = 16
    public static let l: CGFloat = 24
    public static let xl: CGFloat = 32
}

public enum SNRadius {
    public static let standard: CGFloat = 12
    public static let small: CGFloat = 10
    public static let large: CGFloat = 14
}

public enum SNFont {
    /// 26/32 semibold
    public static let title = Font.system(size: 26, weight: .semibold)
    /// 18/24 semibold
    public static let section = Font.system(size: 18, weight: .semibold)
    /// 14/20 medium
    public static let rowTitle = Font.system(size: 14, weight: .medium)
    /// 16/25 regular
    public static let body = Font.system(size: 16)
    /// 12–13/18
    public static let secondary = Font.system(size: 12.5)
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

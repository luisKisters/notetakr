import Foundation

// MARK: - RGBA

public struct RGBA: Equatable {
    public let r: Double
    public let g: Double
    public let b: Double
    public let a: Double

    public init(r: Double, g: Double, b: Double, a: Double = 1.0) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    // Convenience: 0–255 integer components (e.g. from hex codes)
    public init(red: Int, green: Int, blue: Int, alpha: Double = 1.0) {
        self.r = Double(red) / 255.0
        self.g = Double(green) / 255.0
        self.b = Double(blue) / 255.0
        self.a = alpha
    }
}

// MARK: - ThemeColors

public struct ThemeColors: Equatable {
    public let background: RGBA
    public let elevatedFill: RGBA
    public let primaryText: RGBA
    public let secondaryText: RGBA
    public let hairline: RGBA
    public let accent: RGBA
    public let destructive: RGBA
}

// MARK: - Theme

/// Platform-neutral design token table. One entry per Appearance case — exhaustive by construction.
/// App layer maps these RGBA values to SwiftUI Color / NSColor as needed.
public enum Theme {

    /// Glass: semi-transparent dark tint + blur (rgba(46,44,54,0.44) overlay).
    public static let glass = ThemeColors(
        background:    RGBA(red: 46, green: 44, blue: 54, alpha: 0.44),
        elevatedFill:  RGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.055),
        primaryText:   RGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.92),
        secondaryText: RGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.60),
        hairline:      RGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.10),
        accent:        RGBA(red: 167, green: 139, blue: 250),   // #A78BFA — light purple for dark bg
        destructive:   RGBA(red: 255, green: 69, blue: 58)      // #FF453A — Apple system red
    )

    /// Dark: solid purple-tinted near-black (#151417).
    public static let dark = ThemeColors(
        background:    RGBA(red: 21, green: 20, blue: 23),      // #151417
        elevatedFill:  RGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.05),
        primaryText:   RGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.92),
        secondaryText: RGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.60),
        hairline:      RGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.10),
        accent:        RGBA(red: 167, green: 139, blue: 250),   // #A78BFA
        destructive:   RGBA(red: 255, green: 69, blue: 58)      // #FF453A
    )

    /// Light: warm paper (#FAF8F4).
    public static let light = ThemeColors(
        background:    RGBA(red: 250, green: 248, blue: 244),   // #FAF8F4
        elevatedFill:  RGBA(r: 0.0, g: 0.0, b: 0.0, a: 0.04),
        primaryText:   RGBA(r: 30.0/255, g: 27.0/255, b: 36.0/255, a: 0.92),
        secondaryText: RGBA(r: 30.0/255, g: 27.0/255, b: 36.0/255, a: 0.56),
        hairline:      RGBA(r: 0.0, g: 0.0, b: 0.0, a: 0.10),
        accent:        RGBA(red: 139, green: 92, blue: 246),    // #8B5CF6 — darker purple on white
        destructive:   RGBA(red: 255, green: 69, blue: 58)      // #FF453A
    )

    /// Returns the token set for the given appearance. Exhaustive switch — compiler catches new cases.
    public static func colors(for appearance: Appearance) -> ThemeColors {
        switch appearance {
        case .glass: return glass
        case .dark:  return dark
        case .light: return light
        }
    }
}

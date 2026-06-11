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
// Mirrors the scoped CSS variables in kit.css .window / .window.t-dark / .window.t-light.

public struct ThemeColors: Equatable {
    // Text hierarchy
    public let background: RGBA
    public let elevatedFill: RGBA
    public let primaryText: RGBA       // --txt  (0.92 opacity)
    public let secondaryText: RGBA     // --txt2 (0.60 opacity)
    public let tertiaryText: RGBA      // --txt3 (0.38–0.42 opacity)
    public let hairline: RGBA          // --hairline
    public let hoverFill: RGBA         // --hover (row/button hover background)

    // Accent + semantic
    public let accent: RGBA            // --accent (purple shade)
    public let destructive: RGBA       // --rec / Apple system red

    // Surface fills
    public let codeBg: RGBA            // --code-bg
    public let panelFill: RGBA         // --panel-fill (props panel background)
    public let fieldFill: RGBA         // --field (input field background)
    public let fieldBorder: RGBA       // --field-line

    // Chip tokens
    public let chipFill: RGBA          // --chip-fill
    public let chipFillHover: RGBA     // --chip-fill-hover
    public let chipLine: RGBA          // --chip-line

    // Control tokens
    public let toggleOff: RGBA         // --tog-off
    public let kbdBackground: RGBA     // --kbd-bg
    public let kbdBorder: RGBA         // --kbd-line

    // Avatar tokens
    public let avatarFill: RGBA        // --av-fill
    public let avatarRing: RGBA        // --av-ring (ring between overlapping avatars)

    // Traffic-light dot (dimmed state)
    public let trafficLightDot: RGBA   // --light-dot
}

// MARK: - DesignConstants
// Global, non-theme values from kit.css :root. Never per-theme — use ThemeColors for that.

public enum DesignConstants {
    // Accent palette (global, not per-theme)
    public static let purple      = RGBA(red: 139, green:  92, blue: 246)  // #8B5CF6
    public static let purpleLight = RGBA(red: 167, green: 139, blue: 250)  // #A78BFA
    public static let recRed      = RGBA(red: 255, green:  69, blue:  58)  // #FF453A
    public static let statusGreen = RGBA(red:  50, green: 215, blue:  75)  // #32D74B
    public static let pauseAmber  = RGBA(red: 255, green: 159, blue:  10)  // #FF9F0A

    // Spatial tokens (pt / radius)
    public static let windowRadius:     Double = 16
    public static let chipRadius:       Double = 7
    public static let propsRadius:      Double = 10
    public static let windowWidth:      Double = 420
    public static let windowHeight:     Double = 620
}

// MARK: - Theme

/// Platform-neutral design token table. One entry per Appearance case — exhaustive by construction.
/// App layer maps these RGBA values to SwiftUI Color / NSColor as needed.
public enum Theme {

    /// Glass: semi-transparent dark tint + blur (rgba(46,44,54,0.44) overlay).
    public static let glass = ThemeColors(
        background:      RGBA(red: 46, green: 44, blue: 54, alpha: 0.44),
        elevatedFill:    RGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.055),
        primaryText:     RGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.92),
        secondaryText:   RGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.60),
        tertiaryText:    RGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.42),
        hairline:        RGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.10),
        hoverFill:       RGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.06),
        accent:          RGBA(red: 167, green: 139, blue: 250),      // #A78BFA
        destructive:     RGBA(red: 255, green:  69, blue:  58),      // #FF453A
        codeBg:          RGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.08),
        panelFill:       RGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.03),
        fieldFill:       RGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.07),
        fieldBorder:     RGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.13),
        chipFill:        RGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.055),
        chipFillHover:   RGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.09),
        chipLine:        RGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.08),
        toggleOff:       RGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.16),
        kbdBackground:   RGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.10),
        kbdBorder:       RGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.18),
        avatarFill:      RGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.10),
        avatarRing:      RGBA(red: 20, green: 19, blue: 24, alpha: 0.9),
        trafficLightDot: RGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.18)
    )

    /// Dark: solid purple-tinted near-black (#151417).
    public static let dark = ThemeColors(
        background:      RGBA(red: 21, green: 20, blue: 23),         // #151417
        elevatedFill:    RGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.05),
        primaryText:     RGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.92),
        secondaryText:   RGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.60),
        tertiaryText:    RGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.42),
        hairline:        RGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.10),
        hoverFill:       RGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.06),
        accent:          RGBA(red: 167, green: 139, blue: 250),      // #A78BFA
        destructive:     RGBA(red: 255, green:  69, blue:  58),      // #FF453A
        codeBg:          RGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.07),
        panelFill:       RGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.03),
        fieldFill:       RGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.07),
        fieldBorder:     RGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.13),
        chipFill:        RGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.05),
        chipFillHover:   RGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.085),
        chipLine:        RGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.08),
        toggleOff:       RGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.14),
        kbdBackground:   RGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.10),
        kbdBorder:       RGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.18),
        avatarFill:      RGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.10),
        avatarRing:      RGBA(red: 21, green: 20, blue: 23),         // matches background
        trafficLightDot: RGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.18)
    )

    /// Light: warm paper (#FAF8F4).
    public static let light = ThemeColors(
        background:      RGBA(red: 250, green: 248, blue: 244),      // #FAF8F4
        elevatedFill:    RGBA(r: 0.0, g: 0.0, b: 0.0, a: 0.04),
        primaryText:     RGBA(r: 30.0/255, g: 27.0/255, b: 36.0/255, a: 0.92),
        secondaryText:   RGBA(r: 30.0/255, g: 27.0/255, b: 36.0/255, a: 0.56),
        tertiaryText:    RGBA(r: 30.0/255, g: 27.0/255, b: 36.0/255, a: 0.40),
        hairline:        RGBA(r: 0.0, g: 0.0, b: 0.0, a: 0.10),
        hoverFill:       RGBA(r: 40.0/255, g: 30.0/255, b: 50.0/255, a: 0.05),
        accent:          RGBA(red: 139, green:  92, blue: 246),      // #8B5CF6
        destructive:     RGBA(red: 255, green:  69, blue:  58),      // #FF453A
        codeBg:          RGBA(r: 0.0, g: 0.0, b: 0.0, a: 0.055),
        panelFill:       RGBA(r: 0.0, g: 0.0, b: 0.0, a: 0.03),
        fieldFill:       RGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.75),
        fieldBorder:     RGBA(r: 0.0, g: 0.0, b: 0.0, a: 0.13),
        chipFill:        RGBA(r: 0.0, g: 0.0, b: 0.0, a: 0.04),
        chipFillHover:   RGBA(r: 0.0, g: 0.0, b: 0.0, a: 0.065),
        chipLine:        RGBA(r: 0.0, g: 0.0, b: 0.0, a: 0.08),
        toggleOff:       RGBA(r: 0.0, g: 0.0, b: 0.0, a: 0.12),
        kbdBackground:   RGBA(r: 0.0, g: 0.0, b: 0.0, a: 0.06),
        kbdBorder:       RGBA(r: 0.0, g: 0.0, b: 0.0, a: 0.14),
        avatarFill:      RGBA(r: 0.0, g: 0.0, b: 0.0, a: 0.07),
        avatarRing:      RGBA(red: 250, green: 248, blue: 244),      // matches background
        trafficLightDot: RGBA(r: 0.0, g: 0.0, b: 0.0, a: 0.14)
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

import AppKit
import SwiftUI
import NoteTakrKit

// MARK: - SwiftUI environment key for theme colours

struct ThemeColorsKey: EnvironmentKey {
    static let defaultValue: ThemeColors = Theme.glass
}

extension EnvironmentValues {
    var themeColors: ThemeColors {
        get { self[ThemeColorsKey.self] }
        set { self[ThemeColorsKey.self] = newValue }
    }
}

// MARK: - Appearance contract

extension Appearance {
    /// Native and SwiftUI controls must use the same scheme as the explicit app
    /// appearance. Glass intentionally uses the dark control chrome because its
    /// design tokens are light-on-dark and the window material is darkened below.
    var colorScheme: ColorScheme {
        self == .light ? .light : .dark
    }

    var nsAppearance: NSAppearance {
        NSAppearance(named: self == .light ? .aqua : .darkAqua)!
    }
}

/// A separate accessibility-only probe used by GUI tests. Keeping this out of
/// the root view prevents SwiftUI from propagating a container identifier/value
/// onto every interactive descendant.
struct AppearanceAccessibilityMarker: View {
    let appearance: Appearance
    let identifier: String

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Appearance")
            .accessibilityValue("Appearance: \(appearance.rawValue)")
            .accessibilityIdentifier(identifier)
            .allowsHitTesting(false)
    }
}

// MARK: - RGBA → SwiftUI Color

extension RGBA {
    var swiftUIColor: Color { Color(red: r, green: g, blue: b, opacity: a) }

    /// AppKit colour, for NSView-backed controls (e.g. the markdown editor).
    var nsColor: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }
}

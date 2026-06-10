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

// MARK: - RGBA → SwiftUI Color

extension RGBA {
    var swiftUIColor: Color { Color(red: r, green: g, blue: b, opacity: a) }
}

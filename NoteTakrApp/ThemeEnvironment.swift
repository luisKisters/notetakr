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

// MARK: - Shared style helpers

extension View {
    /// Selected state: purple tint background + hairline border.
    /// Use this for the currently-selected item in a list or palette.
    func themeSelectedBackground(_ colors: ThemeColors, cornerRadius: CGFloat = 9) -> some View {
        self.background(
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(colors.accent.swiftUIColor.opacity(0.18))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(colors.accent.swiftUIColor.opacity(0.40), lineWidth: 1)
                )
        )
    }

    /// Hover state: subtle neutral gray fill.
    /// Do NOT use on elements that already have a purple selected state — use gray hover only.
    func themeHoverBackground(_ colors: ThemeColors, isHovered: Bool, cornerRadius: CGFloat = 9) -> some View {
        self.background(
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(isHovered ? colors.hoverFill.swiftUIColor : Color.clear)
        )
    }
}

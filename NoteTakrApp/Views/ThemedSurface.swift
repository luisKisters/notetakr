import SwiftUI
import NoteTakrKit

/// Unified themed surface used for window body, ⌘K palette, settings, and menus.
/// Glass: real macOS backdrop blur (no purple tint, no scrim) + a faint white lift.
/// Dark/Light: solid themed background.
struct ThemedSurface: View {
    let appearance: Appearance

    var body: some View {
        switch appearance {
        case .glass:
            ZStack {
                VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                Theme.glass.background.swiftUIColor
            }
        case .dark:
            Theme.dark.background.swiftUIColor
        case .light:
            Theme.light.background.swiftUIColor
        }
    }
}

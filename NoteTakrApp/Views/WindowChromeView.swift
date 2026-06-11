import SwiftUI
import NoteTakrKit

/// Window chrome bar: real native close button top-left (managed by NSPanel), gear button top-right.
/// Fake traffic-light circles are removed — the real close button lives in the window titlebar.
struct WindowChromeView: View {
    @Environment(\.themeColors) private var theme
    let settingsIsVisible: Bool
    let onGearTap: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            // Reserve space on the left for the native close button (positioned by NSPanel).
            Spacer().frame(width: 52)
            Spacer()
            gearButton
        }
        .frame(height: 40)
        .padding(.horizontal, 13)
    }

    // MARK: - Gear button

    private var gearButton: some View {
        Button(action: onGearTap) {
            Image(systemName: "gearshape")
                .font(.system(size: 13, weight: .light))
                .foregroundStyle(theme.primaryText.swiftUIColor)
                .frame(width: 26, height: 26)
                .background(settingsIsVisible ? theme.hoverFill.swiftUIColor : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .opacity(settingsIsVisible ? 0.95 : 0.5)
        .animation(.easeInOut(duration: 0.18), value: settingsIsVisible)
        .accessibilityIdentifier("settingsGearButton")
        .accessibilityLabel("Settings")
    }
}

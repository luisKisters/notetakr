import SwiftUI
import NoteTakrKit

/// Window chrome bar: traffic lights top-left, gear button top-right.
/// Matches kit.css `.chrome` + `.lights` + `.gear`.
struct WindowChromeView: View {
    @Environment(\.themeColors) private var theme
    let settingsIsVisible: Bool
    let onGearTap: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 0) {
            trafficLights
            Spacer()
            gearButton
        }
        .frame(height: 40)
        .padding(.horizontal, 13)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
    }

    // MARK: - Traffic lights

    private var trafficLights: some View {
        HStack(spacing: 8) {
            trafficDot(hoverColor: Color(red: 1.0, green: 0.373, blue: 0.341))  // close #ff5f57
            trafficDot(hoverColor: Color(red: 0.996, green: 0.737, blue: 0.180)) // minimize #febc2e
            trafficDot(hoverColor: Color(red: 0.157, green: 0.784, blue: 0.251)) // zoom #28c840
        }
    }

    private func trafficDot(hoverColor: Color) -> some View {
        Circle()
            .fill(isHovering ? hoverColor : theme.trafficLightDot.swiftUIColor)
            .frame(width: 12, height: 12)
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

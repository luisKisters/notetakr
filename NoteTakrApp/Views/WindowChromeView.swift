import SwiftUI
import NoteTakrKit

/// Window chrome bar: dimmed traffic lights at rest, hover-color lights, and a hover-only gear.
struct WindowChromeView: View {
    @Environment(\.themeColors) private var theme
    let isWindowHovered: Bool
    let settingsIsVisible: Bool
    let onGearTap: () -> Void
    @State private var gearHovered = false

    var body: some View {
        HStack(spacing: 0) {
            trafficLights
            Spacer()
            gearButton
        }
        .frame(height: 40)
        .padding(.horizontal, 13)
    }

    private var trafficLights: some View {
        HStack(spacing: 8) {
            trafficLight(fill: isWindowHovered ? Color(red: 1.0, green: 0.37, blue: 0.34)
                                               : theme.trafficLightDot.swiftUIColor)
            trafficLight(fill: isWindowHovered ? Color(red: 1.0, green: 0.74, blue: 0.18)
                                               : theme.trafficLightDot.swiftUIColor)
            trafficLight(fill: isWindowHovered ? Color(red: 0.16, green: 0.78, blue: 0.25)
                                               : theme.trafficLightDot.swiftUIColor)
        }
        .frame(width: 52, alignment: .leading)
    }

    private func trafficLight(fill: Color) -> some View {
        Circle()
            .fill(fill)
            .frame(width: 12, height: 12)
            .overlay(Circle().stroke(Color.black.opacity(0.16), lineWidth: 0.5))
            .animation(.easeInOut(duration: 0.18), value: isWindowHovered)
    }

    // MARK: - Gear button

    private var gearButton: some View {
        Button(action: onGearTap) {
            Image(systemName: "gearshape")
                .font(.system(size: 13, weight: .light))
                .foregroundStyle(theme.primaryText.swiftUIColor)
                .frame(width: 26, height: 26)
                .background((settingsIsVisible || gearHovered) ? theme.hoverFill.swiftUIColor : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .opacity(gearOpacity)
        .onHover { gearHovered = $0 }
        .animation(.easeInOut(duration: 0.18), value: settingsIsVisible)
        .animation(.easeInOut(duration: 0.18), value: isWindowHovered)
        .animation(.easeInOut(duration: 0.12), value: gearHovered)
        .accessibilityIdentifier("settingsGearButton")
        .accessibilityLabel("Settings")
    }

    private var gearOpacity: Double {
        if settingsIsVisible { return 0.95 }
        if gearHovered { return 0.9 }
        return isWindowHovered ? 0.28 : 0.0
    }
}

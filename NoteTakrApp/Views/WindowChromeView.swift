import SwiftUI
import NoteTakrKit

/// Window chrome bar: dimmed traffic lights at rest and hover-color lights.
struct WindowChromeView: View {
    @Environment(\.themeColors) private var theme
    let isWindowHovered: Bool

    var body: some View {
        HStack(spacing: 0) {
            trafficLights
            Spacer()
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

}

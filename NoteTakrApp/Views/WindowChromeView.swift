import SwiftUI
import NoteTakrKit

/// Compact title-bar controls for the floating panel. A floating note panel
/// doesn't minimize or zoom, so it exposes only Close plus its two app actions.
struct WindowChromeView: View {
    @Environment(\.themeColors) private var theme
    let close: () -> Void
    let openCommandMenu: () -> Void
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ClosePanelButton(action: close)
            Spacer()
            chromeButton(
                icon: "command",
                help: "Open command menu (⌘K)",
                accessibilityIdentifier: "toolbarCommandKButton",
                action: openCommandMenu
            )
            chromeButton(
                icon: "gearshape",
                help: "Settings (⌘,)",
                accessibilityIdentifier: "toolbarSettingsButton",
                action: openSettings
            )
        }
        .frame(height: 40)
        .padding(.horizontal, DesignConstants.contentInset)
    }

    private func chromeButton(
        icon: String,
        help: String,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        ChromeIconButton(
            icon: icon,
            help: help,
            accessibilityIdentifier: accessibilityIdentifier,
            action: action
        )
        .environment(\.themeColors, theme)
    }
}

private struct ClosePanelButton: View {
    @Environment(\.themeColors) private var theme
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isHovering
                          ? Color(red: 1.0, green: 0.37, blue: 0.34)
                          : theme.trafficLightDot.swiftUIColor)
                if isHovering {
                    Image(systemName: "xmark")
                        .font(.system(size: 6.5, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.58))
                }
            }
            .frame(width: 12, height: 12)
            .overlay(Circle().stroke(Color.black.opacity(0.16), lineWidth: 0.5))
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .frame(width: 20, height: 24, alignment: .leading)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .help("Close")
        .accessibilityLabel("Close")
        .accessibilityIdentifier("toolbarCloseButton")
    }
}

private struct ChromeIconButton: View {
    @Environment(\.themeColors) private var theme
    let icon: String
    let help: String
    let accessibilityIdentifier: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(theme.secondaryText.swiftUIColor)
                .frame(width: 26, height: 24)
                .contentShape(RoundedRectangle(cornerRadius: 6))
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHovering ? theme.hoverFill.swiftUIColor : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isHovering ? theme.hairline.swiftUIColor : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(help)
        .accessibilityLabel(help)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

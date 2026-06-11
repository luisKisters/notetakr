import SwiftUI
import NoteTakrKit

/// Keyboard shortcut pill. Matches kit.css `kbd`.
struct KbdPillView: View {
    @Environment(\.themeColors) private var theme
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(theme.secondaryText.swiftUIColor)
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(theme.kbdBackground.swiftUIColor)
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(theme.kbdBorder.swiftUIColor, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}

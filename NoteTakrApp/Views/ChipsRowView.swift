import SwiftUI
import NoteTakrKit

/// Compact frontmatter summary chips below the title.
/// The record pill is always the first element with its own tap handler.
/// Tapping anywhere else on the row toggles the property panel expansion.
struct ChipsRowView: View {
    @ObservedObject var bridge: FrontmatterPresenterBridge
    let machine: RecordPillStateMachine
    let pillState: RecordPillState
    let onRecordPillIdleTap: (() -> Void)?
    @Environment(\.themeColors) private var theme

    // Tracks hover only over the chips area — NOT over the RecordPillView.
    // This prevents the record badge's hover from restyling the time/clock chip.
    @State private var isChipsAreaHovering = false
    @State private var isChevronHovering = false

    var body: some View {
        // The outer button covers the whole row for expand toggle.
        // RecordPillView (nested Button) intercepts taps within its own bounds.
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { bridge.isExpanded.toggle() }
        } label: {
            HStack(spacing: 0) {
                RecordPillView(
                    machine: machine,
                    pillState: pillState,
                    onIdleTapOverride: onRecordPillIdleTap
                )
                    .environment(\.themeColors, theme)
                    .padding(.trailing, 6)

                // Vertical divider
                Rectangle()
                    .fill(theme.hairline.swiftUIColor)
                    .frame(width: 1, height: 11)
                    .padding(.trailing, 9)

                // Non-recording chips (recording chip removed — pill handles the display)
                HStack(spacing: 6) {
                    ForEach(Array(nonRecordingChips.enumerated()), id: \.offset) { _, chip in
                        chipView(chip)
                    }
                }
                .onHover { isChipsAreaHovering = $0 }

                Spacer(minLength: 0)

                chevron
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.bottom, 2)
    }

    private var nonRecordingChips: [Chip] {
        bridge.chips.filter {
            if case .recording = $0 { return false }
            return true
        }
    }

    @ViewBuilder
    private func chipView(_ chip: Chip) -> some View {
        switch chip {
        case .timeRange(let label):
            TimeChip(label: label, theme: theme, isRowHovered: isChipsAreaHovering)
        case .location(let label):
            LocationChip(label: label, theme: theme, isRowHovered: isChipsAreaHovering)
        case .participants(let label):
            ParticipantsChip(
                label: label,
                participants: bridge.participants,
                theme: theme,
                isRowHovered: isChipsAreaHovering
            )
        case .recording:
            EmptyView()
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.down")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(isChevronHovering
                             ? theme.primaryText.swiftUIColor
                             : theme.tertiaryText.swiftUIColor)
            .rotationEffect(.degrees(bridge.isExpanded ? 180 : 0))
            .animation(.easeInOut(duration: 0.2), value: bridge.isExpanded)
            // Comfortable, obvious hit target (whole pill toggles too, but this gives
            // a clear affordance with a hover highlight instead of a 10pt glyph).
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isChevronHovering ? theme.hoverFill.swiftUIColor : Color.clear)
            )
            .contentShape(Rectangle())
            .onHover { isChevronHovering = $0 }
    }
}

// MARK: - Individual chip shapes

private struct TimeChip: View {
    let label: String
    let theme: ThemeColors
    let isRowHovered: Bool

    var body: some View {
        ChipContainer(theme: theme, isRowHovered: isRowHovered) {
            Image(systemName: "clock")
                .font(.system(size: 10, weight: .light))
                .opacity(0.78)
            Text(label)
                .font(.system(size: 11.5))
                .fontDesign(.monospaced)
        }
    }
}

private struct LocationChip: View {
    let label: String
    let theme: ThemeColors
    let isRowHovered: Bool

    private var iconName: String {
        switch label {
        case "Zoom", "Google Meet", "Teams": return "video"
        default: return "person.2"
        }
    }

    var body: some View {
        ChipContainer(theme: theme, isRowHovered: isRowHovered) {
            Image(systemName: iconName)
                .font(.system(size: 10, weight: .light))
                .opacity(0.78)
            Text(label)
                .font(.system(size: 11.5))
        }
    }
}

private struct ParticipantsChip: View {
    let label: String
    let participants: [Participant]
    let theme: ThemeColors
    let isRowHovered: Bool

    private var visibleInitials: [String] {
        Array(participants.prefix(3)).map { String($0.name.prefix(1)).uppercased() }
    }

    var body: some View {
        ChipContainer(theme: theme, isRowHovered: isRowHovered, leadingPadding: 6) {
            HStack(spacing: -5) {
                ForEach(Array(visibleInitials.enumerated()), id: \.offset) { _, initial in
                    AvatarCircle(initial: initial, theme: theme)
                }
            }
            Text(label)
                .font(.system(size: 11.5))
        }
    }
}


private struct AvatarCircle: View {
    let initial: String
    let theme: ThemeColors

    var body: some View {
        Text(initial)
            .font(.system(size: 8.5, weight: .semibold))
            .foregroundStyle(theme.secondaryText.swiftUIColor)
            .frame(width: 16, height: 16)
            .background(theme.avatarFill.swiftUIColor)
            .clipShape(Circle())
            .overlay(
                Circle().stroke(theme.chipLine.swiftUIColor, lineWidth: 1)
            )
            .background(
                Circle().fill(theme.avatarRing.swiftUIColor).padding(-1.5)
            )
    }
}

private struct ChipContainer<Content: View>: View {
    let theme: ThemeColors
    let isRowHovered: Bool
    let leadingPadding: CGFloat
    let content: Content

    init(
        theme: ThemeColors,
        isRowHovered: Bool,
        leadingPadding: CGFloat = 9,
        @ViewBuilder content: () -> Content
    ) {
        self.theme = theme
        self.isRowHovered = isRowHovered
        self.leadingPadding = leadingPadding
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 5.5) {
            content
        }
        .foregroundStyle(
            isRowHovered
                ? theme.primaryText.swiftUIColor
                : theme.secondaryText.swiftUIColor
        )
        .frame(height: 24)
        .padding(.leading, leadingPadding)
        .padding(.trailing, 9)
        .background(
            isRowHovered
                ? theme.chipFillHover.swiftUIColor
                : theme.chipFill.swiftUIColor
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignConstants.chipRadius)
                .stroke(theme.chipLine.swiftUIColor, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: DesignConstants.chipRadius))
        .animation(.easeInOut(duration: 0.15), value: isRowHovered)
    }
}

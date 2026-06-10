import SwiftUI
import NoteTakrKit

/// Compact frontmatter summary chips below the title.
/// Tapping the row toggles the property panel expansion.
struct ChipsRowView: View {
    @ObservedObject var bridge: FrontmatterPresenterBridge

    var body: some View {
        Button {
            bridge.isExpanded.toggle()
        } label: {
            HStack(spacing: 6) {
                ForEach(Array(bridge.chips.enumerated()), id: \.offset) { _, chip in
                    chipView(chip)
                }
                chevron
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.bottom, 6)
    }

    // MARK: - Chip views

    @ViewBuilder
    private func chipView(_ chip: Chip) -> some View {
        switch chip {
        case .timeRange(let label):
            TimeChip(label: label)
        case .location(let label):
            LocationChip(label: label)
        case .participants(let label):
            ParticipantsChip(
                label: label,
                participants: bridge.participants
            )
        case .recording(let elapsed):
            RecordingChip(elapsed: elapsed)
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.down")
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(Color.white.opacity(0.4))
            .rotationEffect(.degrees(bridge.isExpanded ? 180 : 0))
            .animation(.easeInOut(duration: 0.2), value: bridge.isExpanded)
    }
}

// MARK: - Individual chip shapes

private struct TimeChip: View {
    let label: String

    var body: some View {
        ChipContainer {
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

    private var iconName: String {
        switch label {
        case "Zoom":    return "video"
        case "Google Meet": return "video"
        case "Teams":   return "video"
        default:        return "person.2"
        }
    }

    var body: some View {
        ChipContainer {
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

    private var visibleInitials: [String] {
        Array(participants.prefix(3)).map { String($0.name.prefix(1)).uppercased() }
    }

    var body: some View {
        ChipContainer(leadingPadding: 6) {
            // Avatar initial circles
            HStack(spacing: -5) {
                ForEach(Array(visibleInitials.enumerated()), id: \.offset) { _, initial in
                    AvatarCircle(initial: initial)
                }
            }
            Text(label)
                .font(.system(size: 11.5))
        }
    }
}

private struct RecordingChip: View {
    let elapsed: String
    @State private var dotVisible = true

    var body: some View {
        ChipContainer {
            Circle()
                .fill(Color.red)
                .frame(width: 6, height: 6)
                .opacity(dotVisible ? 1 : 0.2)
                .animation(.easeInOut(duration: 0.7).repeatForever(), value: dotVisible)
                .onAppear { dotVisible = false }
            Text(elapsed)
                .font(.system(size: 11.5))
                .fontDesign(.monospaced)
        }
    }
}

private struct AvatarCircle: View {
    let initial: String

    var body: some View {
        Text(initial)
            .font(.system(size: 8.5, weight: .semibold))
            .foregroundColor(Color.white.opacity(0.7))
            .frame(width: 16, height: 16)
            .background(Color.white.opacity(0.12))
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 1))
    }
}

private struct ChipContainer<Content: View>: View {
    let leadingPadding: CGFloat
    let content: Content

    init(leadingPadding: CGFloat = 9, @ViewBuilder content: () -> Content) {
        self.leadingPadding = leadingPadding
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 5.5) {
            content
        }
        .foregroundColor(Color.white.opacity(0.55))
        .frame(height: 24)
        .padding(.leading, leadingPadding)
        .padding(.trailing, 9)
        .background(Color.white.opacity(0.07))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}

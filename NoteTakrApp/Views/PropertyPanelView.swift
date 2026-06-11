import SwiftUI
import NoteTakrKit

/// Expandable property rows below the chips row.
struct PropertyPanelView: View {
    @ObservedObject var bridge: FrontmatterPresenterBridge
    @Environment(\.themeColors) private var theme

    var body: some View {
        if bridge.isExpanded {
            VStack(spacing: 0) {
                ForEach(Array(bridge.propertyRows.enumerated()), id: \.offset) { idx, row in
                    PropertyRowView(
                        row: row,
                        isLast: idx == bridge.propertyRows.count - 1,
                        bridge: bridge,
                        theme: theme
                    )
                }
            }
            .background(theme.panelFill.swiftUIColor)
            .overlay(
                RoundedRectangle(cornerRadius: DesignConstants.propsRadius)
                    .stroke(theme.hairline.swiftUIColor, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: DesignConstants.propsRadius))
            .padding(.horizontal, 20)
            .padding(.bottom, 6)
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .offset(y: -4)),
                removal: .opacity
            ))
        }
    }
}

// MARK: - Single row

private struct PropertyRowView: View {
    let row: PropertyRow
    let isLast: Bool
    @ObservedObject var bridge: FrontmatterPresenterBridge
    let theme: ThemeColors

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            keyView
            Spacer()
            valueView
        }
        .frame(minHeight: 36)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(theme.hairline.swiftUIColor)
                    .frame(height: 1)
            }
        }
    }

    @ViewBuilder
    private var keyView: some View {
        switch row {
        case .date:
            KeyLabel(icon: "calendar", label: "Date", theme: theme)
        case .calendarEvent:
            KeyLabel(icon: "link", label: "Calendar event", theme: theme)
        case .participants:
            KeyLabel(icon: "person.2", label: "Participants", theme: theme)
        case .location:
            KeyLabel(icon: "mappin", label: "Location", theme: theme)
        case .inPerson:
            KeyLabel(icon: "figure.walk", label: "In person", theme: theme)
        case .transcribe:
            KeyLabel(icon: "mic", label: "Transcribe", theme: theme)
        }
    }

    @ViewBuilder
    private var valueView: some View {
        switch row {
        case .date(let date):
            DateValue(date: date, theme: theme)
        case .calendarEvent(let name):
            CalendarEventValue(name: name, bridge: bridge, theme: theme)
        case .participants(let list):
            ParticipantsValue(participants: list, theme: theme)
        case .location(let loc):
            Text(locationText(loc))
                .font(.system(size: 12))
                .foregroundStyle(theme.primaryText.swiftUIColor.opacity(0.85))
        case .inPerson(let on):
            Toggle("", isOn: Binding(
                get: { on },
                set: { bridge.setInPerson($0) }
            ))
            .toggleStyle(ThemedToggleStyle(theme: theme))
            .labelsHidden()
        case .transcribe(let on):
            Text(on.map { $0 ? "On" : "Off" } ?? "—")
                .font(.system(size: 12))
                .foregroundStyle(theme.primaryText.swiftUIColor.opacity(0.85))
        }
    }

    private func locationText(_ loc: Location?) -> String {
        guard let loc else { return "—" }
        switch loc {
        case .zoom:     return "Zoom"
        case .meet:     return "Google Meet"
        case .teams:    return "Teams"
        case .inPerson: return "In person"
        case .none:     return "—"
        }
    }
}

// MARK: - Value sub-views

private struct DateValue: View {
    let date: Date
    let theme: ThemeColors

    private var formatted: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }

    var body: some View {
        Text(formatted)
            .font(.system(size: 12).monospacedDigit())
            .foregroundStyle(theme.secondaryText.swiftUIColor)
    }
}

private struct CalendarEventValue: View {
    let name: String?
    @ObservedObject var bridge: FrontmatterPresenterBridge
    let theme: ThemeColors

    var body: some View {
        HStack(spacing: 8) {
            Text(name ?? "Not linked")
                .font(.system(size: 12))
                .foregroundStyle(
                    name != nil
                        ? theme.primaryText.swiftUIColor.opacity(0.85)
                        : theme.tertiaryText.swiftUIColor
                )
            if name != nil {
                Button("Unlink") {
                    bridge.unlinkEvent()
                }
                .font(.system(size: 11))
                .foregroundStyle(theme.tertiaryText.swiftUIColor)
                .buttonStyle(.plain)
            }
        }
    }
}

private struct ParticipantsValue: View {
    let participants: [Participant]
    let theme: ThemeColors

    var body: some View {
        if participants.isEmpty {
            Text("—")
                .font(.system(size: 12))
                .foregroundStyle(theme.tertiaryText.swiftUIColor)
        } else {
            Text(participants.map(\.name).joined(separator: ", "))
                .font(.system(size: 12))
                .foregroundStyle(theme.primaryText.swiftUIColor.opacity(0.85))
                .lineLimit(1)
        }
    }
}

private struct KeyLabel: View {
    let icon: String
    let label: String
    let theme: ThemeColors

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(theme.tertiaryText.swiftUIColor)
                .frame(width: 13, height: 13)
            Text(label)
                .font(.system(size: 11.5))
                .foregroundStyle(theme.tertiaryText.swiftUIColor)
        }
        .frame(minWidth: 92, alignment: .leading)
    }
}

// MARK: - Theme-aware toggle style

private struct ThemedToggleStyle: ToggleStyle {
    let theme: ThemeColors

    func makeBody(configuration: Configuration) -> some View {
        RoundedRectangle(cornerRadius: 99)
            .fill(configuration.isOn
                  ? theme.accent.swiftUIColor
                  : theme.toggleOff.swiftUIColor)
            .frame(width: 30, height: 18)
            .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                Circle()
                    .fill(Color.white)
                    .frame(width: 14, height: 14)
                    .shadow(radius: 1, y: 1)
                    .padding(2)
            }
            .animation(.easeInOut(duration: 0.2), value: configuration.isOn)
            .onTapGesture { configuration.isOn.toggle() }
    }
}

import SwiftUI
import NoteTakrKit

/// Expandable property rows below the chips row.
struct PropertyPanelView: View {
    @ObservedObject var bridge: FrontmatterPresenterBridge

    var body: some View {
        if bridge.isExpanded {
            VStack(spacing: 0) {
                ForEach(Array(bridge.propertyRows.enumerated()), id: \.offset) { idx, row in
                    PropertyRowView(
                        row: row,
                        isLast: idx == bridge.propertyRows.count - 1,
                        bridge: bridge
                    )
                }
            }
            .background(Color.white.opacity(0.05))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
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

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            keyView
            Spacer()
            valueView
        }
        .frame(minHeight: 34)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 1)
            }
        }
    }

    @ViewBuilder
    private var keyView: some View {
        switch row {
        case .date:
            KeyLabel(icon: "calendar", label: "Date")
        case .calendarEvent:
            KeyLabel(icon: "link", label: "Calendar event")
        case .participants:
            KeyLabel(icon: "person.2", label: "Participants")
        case .location:
            KeyLabel(icon: "mappin", label: "Location")
        case .inPerson:
            KeyLabel(icon: "figure.walk", label: "In person")
        case .transcribe:
            KeyLabel(icon: "mic", label: "Transcribe")
        }
    }

    @ViewBuilder
    private var valueView: some View {
        switch row {
        case .date(let date):
            DateValue(date: date)
        case .calendarEvent(let name):
            CalendarEventValue(name: name, bridge: bridge)
        case .participants(let list):
            ParticipantsValue(participants: list)
        case .location(let loc):
            Text(locationText(loc))
                .font(.system(size: 12))
                .foregroundColor(Color.white.opacity(0.85))
        case .inPerson(let on):
            Toggle("", isOn: Binding(
                get: { on },
                set: { bridge.setInPerson($0) }
            ))
            .toggleStyle(PurpleToggleStyle())
            .labelsHidden()
        case .transcribe(let on):
            Text(on.map { $0 ? "On" : "Off" } ?? "—")
                .font(.system(size: 12))
                .foregroundColor(Color.white.opacity(0.85))
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

    private var formatted: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }

    var body: some View {
        Text(formatted)
            .font(.system(size: 12).monospacedDigit())
            .foregroundColor(Color.white.opacity(0.55))
    }
}

private struct CalendarEventValue: View {
    let name: String?
    @ObservedObject var bridge: FrontmatterPresenterBridge

    var body: some View {
        HStack(spacing: 8) {
            Text(name ?? "Not linked")
                .font(.system(size: 12))
                .foregroundColor(name != nil ? Color.white.opacity(0.85) : Color.white.opacity(0.3))
            if name != nil {
                Button("Unlink") {
                    bridge.unlinkEvent()
                }
                .font(.system(size: 11))
                .foregroundColor(Color.white.opacity(0.4))
                .buttonStyle(.plain)
            }
        }
    }
}

private struct ParticipantsValue: View {
    let participants: [Participant]

    var body: some View {
        if participants.isEmpty {
            Text("—")
                .font(.system(size: 12))
                .foregroundColor(Color.white.opacity(0.3))
        } else {
            Text(participants.map(\.name).joined(separator: ", "))
                .font(.system(size: 12))
                .foregroundColor(Color.white.opacity(0.85))
                .lineLimit(1)
        }
    }
}

private struct KeyLabel: View {
    let icon: String
    let label: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(Color.white.opacity(0.35))
                .frame(width: 13, height: 13)
            Text(label)
                .font(.system(size: 11.5))
                .foregroundColor(Color.white.opacity(0.35))
        }
    }
}

// MARK: - Custom toggle style

private struct PurpleToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        RoundedRectangle(cornerRadius: 99)
            .fill(configuration.isOn
                  ? Color(red: 0.545, green: 0.361, blue: 0.965)
                  : Color.white.opacity(0.2))
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

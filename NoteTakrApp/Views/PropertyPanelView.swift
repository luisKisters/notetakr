import SwiftUI
import NoteTakrKit

/// Expandable property rows below the chips row, matching frontmatter.html.
/// Nothing looks editable until hover; click a field to edit.
struct PropertyPanelView: View {
    @ObservedObject var bridge: FrontmatterPresenterBridge
    let recordPillMachine: RecordPillStateMachine
    let pillState: RecordPillState
    let availableEvents: [UpcomingEvent]
    @Environment(\.themeColors) private var theme

    var body: some View {
        if bridge.isExpanded {
            VStack(spacing: 0) {
                ForEach(Array(bridge.propertyRows.enumerated()), id: \.offset) { idx, row in
                    PropertyRowView(
                        row: row,
                        isLast: idx == bridge.propertyRows.count - 1,
                        bridge: bridge,
                        machine: recordPillMachine,
                        pillState: pillState,
                        availableEvents: availableEvents,
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
    let machine: RecordPillStateMachine
    let pillState: RecordPillState
    let availableEvents: [UpcomingEvent]
    let theme: ThemeColors

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            keyView
                .padding(.top, 2)
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
        case .event:
            KeyLabel(icon: "calendar", label: "Event", theme: theme)
        case .dateTime:
            KeyLabel(icon: "clock", label: "Date & time", theme: theme)
        case .people:
            KeyLabel(icon: "person.2", label: "People", theme: theme)
        case .location:
            KeyLabel(icon: "mappin", label: "Location", theme: theme)
        case .meetingLink:
            KeyLabel(icon: "link", label: "Meeting link", theme: theme)
        case .inPerson:
            KeyLabel(icon: "figure.walk", label: "In-person", theme: theme)
        case .transcript:
            KeyLabel(icon: "mic", label: "Transcript", theme: theme)
        }
    }

    @ViewBuilder
    private var valueView: some View {
        switch row {
        case .event(let id, let title):
            EventChipValue(
                linkedID: id,
                displayTitle: title,
                availableEvents: availableEvents,
                bridge: bridge,
                theme: theme
            )
        case .dateTime(let date, let end):
            DateTimeValue(date: date, end: end, bridge: bridge, theme: theme)
        case .people(let participants):
            PeopleValue(participants: participants, bridge: bridge, theme: theme)
        case .location(let text):
            EditableTextValue(
                value: text ?? "",
                placeholder: "No location",
                theme: theme,
                onCommit: { bridge.setLocationText($0) }
            )
        case .meetingLink(let link):
            EditableTextValue(
                value: link ?? "",
                placeholder: "No link",
                theme: theme,
                onCommit: { bridge.setMeetingLink($0) }
            )
        case .inPerson(let on):
            InPersonValue(isOn: on, bridge: bridge, theme: theme)
        case .transcript:
            TranscriptRowValue(
                bridge: bridge,
                machine: machine,
                pillState: pillState,
                theme: theme
            )
        }
    }
}

// MARK: - Key label

private struct KeyLabel: View {
    let icon: String
    let label: String
    let theme: ThemeColors

    var body: some View {
        HStack(spacing: 6) {
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

// MARK: - Event chip value

private struct EventChipValue: View {
    let linkedID: String?
    let displayTitle: String
    let availableEvents: [UpcomingEvent]
    @ObservedObject var bridge: FrontmatterPresenterBridge
    let theme: ThemeColors

    @State private var showMenu = false

    private var isLinked: Bool { linkedID != nil }

    var body: some View {
        Button {
            showMenu.toggle()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "calendar")
                    .font(.system(size: 10))
                    .foregroundStyle(theme.tertiaryText.swiftUIColor)
                Text(isLinked ? displayTitle : "Not linked")
                    .font(.system(size: 12))
                    .foregroundStyle(
                        isLinked
                            ? theme.primaryText.swiftUIColor.opacity(0.85)
                            : theme.tertiaryText.swiftUIColor
                    )
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9))
                    .foregroundStyle(theme.tertiaryText.swiftUIColor)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(theme.chipFill.swiftUIColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(theme.hairline.swiftUIColor, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showMenu, arrowEdge: .bottom) {
            EventPickerMenu(
                availableEvents: availableEvents,
                isLinked: isLinked,
                bridge: bridge,
                dismiss: { showMenu = false }
            )
        }
    }
}

private struct EventPickerMenu: View {
    let availableEvents: [UpcomingEvent]
    let isLinked: Bool
    @ObservedObject var bridge: FrontmatterPresenterBridge
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Link a calendar event")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 4)

            if availableEvents.isEmpty {
                Text("No upcoming events")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
            } else {
                ForEach(availableEvents, id: \.id) { event in
                    Button {
                        bridge.linkCalendarEvent(
                            id: event.id,
                            title: event.title,
                            attendees: event.participants.map { (name: $0.name, email: $0.email) },
                            startDate: event.start,
                            endDate: event.end,
                            locationText: event.locationText,
                            meetingLink: event.meetingLink
                        )
                        dismiss()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "calendar")
                                .font(.system(size: 11))
                                .frame(width: 13)
                            Text(event.title)
                                .font(.system(size: 12))
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                if isLinked {
                    Divider().padding(.horizontal, 6)

                    Button {
                        bridge.unlinkEvent()
                        dismiss()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "xmark")
                                .font(.system(size: 11))
                                .frame(width: 13)
                            Text("— No event —")
                                .font(.system(size: 12))
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(minWidth: 220)
        .padding(.bottom, 4)
    }
}

// MARK: - Date & time value

private struct DateTimeValue: View {
    let date: Date
    let end: Date?
    @ObservedObject var bridge: FrontmatterPresenterBridge
    let theme: ThemeColors

    @State private var showDatePicker = false
    @State private var isHoveringDate = false

    private var dateLabel: String {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f.string(from: date)
    }

    private var timeLabel: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        let start = f.string(from: date)
        guard let end else { return start }
        return "\(start)–\(f.string(from: end))"
    }

    var body: some View {
        HStack(spacing: 6) {
            Button {
                showDatePicker.toggle()
            } label: {
                Text(dateLabel)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.primaryText.swiftUIColor.opacity(0.85))
                    .underline(isHoveringDate, color: theme.hairline.swiftUIColor)
            }
            .buttonStyle(.plain)
            .onHover { isHoveringDate = $0 }
            .popover(isPresented: $showDatePicker, arrowEdge: .bottom) {
                DatePickerPopover(date: date, end: end, bridge: bridge) {
                    showDatePicker = false
                }
            }

            Text("·")
                .font(.system(size: 12))
                .foregroundStyle(theme.tertiaryText.swiftUIColor)

            Text(timeLabel)
                .font(.system(size: 12, design: .monospaced).monospacedDigit())
                .foregroundStyle(theme.secondaryText.swiftUIColor)
        }
    }
}

private struct DatePickerPopover: View {
    let date: Date
    let end: Date?
    @ObservedObject var bridge: FrontmatterPresenterBridge
    let dismiss: () -> Void
    @State private var selectedDate: Date

    init(date: Date, end: Date?, bridge: FrontmatterPresenterBridge, dismiss: @escaping () -> Void) {
        self.date = date
        self.end = end
        self.bridge = bridge
        self.dismiss = dismiss
        self._selectedDate = State(initialValue: date)
    }

    var body: some View {
        VStack(spacing: 8) {
            DatePicker(
                "",
                selection: $selectedDate,
                displayedComponents: [.date, .hourAndMinute]
            )
            .labelsHidden()
            .datePickerStyle(.graphical)
            .frame(width: 260)

            Button("Done") {
                bridge.setDate(selectedDate, end: end)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(.accentColor)
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }
}

// MARK: - People circles value

private struct PeopleValue: View {
    let participants: [Participant]
    @ObservedObject var bridge: FrontmatterPresenterBridge
    let theme: ThemeColors

    @State private var hoveredParticipant: Participant? = nil
    @State private var menuParticipant: Participant? = nil
    @State private var showAddField = false
    @State private var newPersonName = ""
    @FocusState private var addFieldFocused: Bool

    var body: some View {
        HStack(spacing: 4) {
            if participants.isEmpty {
                Text("—")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.tertiaryText.swiftUIColor)
            } else {
                ForEach(Array(participants.enumerated()), id: \.offset) { _, participant in
                    participantCircle(participant)
                }
            }

            // Add field — fixed width prevents layout shift when toggling between
            // the "+" avatar button and the name TextField.
            Group {
                if showAddField {
                    TextField("Name…", text: $newPersonName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(theme.hairline.swiftUIColor, lineWidth: 1)
                        )
                        .focused($addFieldFocused)
                        .onSubmit { commitAdd() }
                        .onExitCommand { cancelAdd() }
                        .onAppear { addFieldFocused = true }
                } else {
                    Button {
                        showAddField = true
                    } label: {
                        Text("+")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(theme.tertiaryText.swiftUIColor)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(theme.chipFill.swiftUIColor))
                            .overlay(Circle().stroke(theme.hairline.swiftUIColor.opacity(0.8), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(width: 88, alignment: .leading)
        }
    }

    @ViewBuilder
    private func participantCircle(_ participant: Participant) -> some View {
        let initials = initials(for: participant.name)
        let isHovered = hoveredParticipant == participant

        ZStack {
            Circle()
                .fill(theme.avatarFill.swiftUIColor)
                .frame(width: 24, height: 24)
            Circle()
                .stroke(theme.hairline.swiftUIColor.opacity(0.8), lineWidth: 1)
                .frame(width: 24, height: 24)

            if isHovered {
                Text("✕")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.red)
            } else {
                Text(initials)
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(theme.secondaryText.swiftUIColor)
            }
        }
        .frame(width: 24, height: 24)
        .onHover { hoveredParticipant = $0 ? participant : nil }
        .onTapGesture {
            menuParticipant = (menuParticipant == participant) ? nil : participant
        }
        .popover(
            isPresented: Binding(
                get: { menuParticipant == participant },
                set: { if !$0 { menuParticipant = nil } }
            ),
            arrowEdge: .bottom
        ) {
            ParticipantMenu(
                participant: participant,
                bridge: bridge,
                dismiss: { menuParticipant = nil }
            )
        }
        .help("\(participant.name)\(participant.email.map { "\n\($0)" } ?? "")\nClick to manage")
    }

    private func initials(for name: String) -> String {
        name.split(separator: " ").prefix(2)
            .compactMap { $0.first.map { String($0).uppercased() } }
            .joined()
    }

    private func commitAdd() {
        let trimmed = newPersonName.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            bridge.addParticipant(name: trimmed)
        }
        newPersonName = ""
        showAddField = false
    }

    private func cancelAdd() {
        newPersonName = ""
        showAddField = false
    }
}

private struct ParticipantMenu: View {
    let participant: Participant
    @ObservedObject var bridge: FrontmatterPresenterBridge
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            VStack(alignment: .leading, spacing: 2) {
                Text(participant.name)
                    .font(.system(size: 12, weight: .medium))
                if let email = participant.email {
                    Text(email)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 4)

            Divider().padding(.horizontal, 6)

            Button {
                bridge.removeParticipant(participant)
                dismiss()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11))
                        .frame(width: 13)
                    Text("Remove from note")
                        .font(.system(size: 12))
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

        }
        .frame(minWidth: 190)
        .padding(.bottom, 4)
    }
}

// MARK: - Editable text value

private struct EditableTextValue: View {
    let value: String
    let placeholder: String
    let theme: ThemeColors
    let onCommit: (String?) -> Void

    @State private var isEditing = false
    @State private var editText = ""
    @State private var isHovering = false
    @FocusState private var focused: Bool

    private var isEmpty: Bool { value.isEmpty }
    private var display: String { isEmpty ? placeholder : value }

    var body: some View {
        if isEditing {
            TextField(placeholder, text: $editText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(theme.primaryText.swiftUIColor)
                .frame(minWidth: 90, alignment: .trailing)
                .focused($focused)
                .onSubmit { commit() }
                .onExitCommand { cancel() }
                .onAppear {
                    editText = value
                    focused = true
                }
        } else {
            Text(display)
                .font(.system(size: 12))
                .foregroundStyle(
                    isEmpty
                        ? theme.tertiaryText.swiftUIColor
                        : theme.primaryText.swiftUIColor.opacity(0.85)
                )
                // Same minWidth as the TextField so entering edit mode doesn't reflow the row.
                .frame(minWidth: 90, alignment: .trailing)
                .underline(isHovering, color: theme.hairline.swiftUIColor)
                .onHover { isHovering = $0 }
                .onTapGesture { isEditing = true }
        }
    }

    private func commit() {
        let trimmed = editText.trimmingCharacters(in: .whitespaces)
        onCommit(trimmed.isEmpty ? nil : trimmed)
        isEditing = false
    }

    private func cancel() {
        isEditing = false
    }
}

// MARK: - In-person value

private struct InPersonValue: View {
    let isOn: Bool
    @ObservedObject var bridge: FrontmatterPresenterBridge
    let theme: ThemeColors

    @State private var showExplainer = false

    var body: some View {
        HStack(spacing: 8) {
            Button {
                showExplainer.toggle()
            } label: {
                Text("?")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(theme.tertiaryText.swiftUIColor)
                    .frame(width: 14, height: 14)
                    .overlay(
                        Circle()
                            .stroke(theme.tertiaryText.swiftUIColor.opacity(0.5), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showExplainer, arrowEdge: .leading) {
                Text("In-person meetings are mic-only — NoteTakr skips system-audio capture.")
                    .font(.system(size: 11.5))
                    .padding(10)
                    .frame(maxWidth: 220)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Toggle("", isOn: Binding(
                get: { isOn },
                set: { bridge.setInPerson($0) }
            ))
            .toggleStyle(ThemedToggleStyle(theme: theme))
            .labelsHidden()
        }
    }
}

// MARK: - Transcript row value

private struct TranscriptRowValue: View {
    @ObservedObject var bridge: FrontmatterPresenterBridge
    let machine: RecordPillStateMachine
    let pillState: RecordPillState
    let theme: ThemeColors

    @State private var audioState: AudioPlaybackState = .idle

    var body: some View {
        if bridge.hasCompletedRecording {
            AudioPlayerView(
                state: audioState,
                onTogglePlay: { togglePlay() },
                onSeek: { _ in }
            )
            .environment(\.themeColors, theme)
            .frame(maxWidth: 180)
        } else {
            RecordPillView(machine: machine, pillState: pillState)
                .environment(\.themeColors, theme)
        }
    }

    private func togglePlay() {
        switch audioState {
        case .ready(let d):
            audioState = .playing(currentTime: 0, duration: d)
        case .playing(let t, let d):
            audioState = .paused(currentTime: t, duration: d)
        case .paused(let t, let d):
            audioState = .playing(currentTime: t, duration: d)
        case .idle:
            break
        }
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

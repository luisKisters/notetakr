import SwiftUI
import NoteTakrKit

/// Expandable property rows below the chips row, matching frontmatter.html.
/// Nothing looks editable until hover; click a field to edit.
struct PropertyPanelView: View {
    @ObservedObject var bridge: FrontmatterPresenterBridge
    let recordPillMachine: RecordPillStateMachine
    let pillState: RecordPillState
    let onRecordPillIdleTap: (() -> Void)?
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
                        onRecordPillIdleTap: onRecordPillIdleTap,
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
    let onRecordPillIdleTap: (() -> Void)?
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
                onRecordPillIdleTap: onRecordPillIdleTap,
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
                theme: theme,
                dismiss: { showMenu = false }
            )
        }
    }
}

private struct EventPickerMenu: View {
    let availableEvents: [UpcomingEvent]
    let isLinked: Bool
    @ObservedObject var bridge: FrontmatterPresenterBridge
    let theme: ThemeColors
    let dismiss: () -> Void

    @State private var searchQuery = ""
    @State private var loadedWindow: EventPickerWindow?

    private var effectiveWindow: EventPickerWindow {
        loadedWindow ?? bridge.availableEventWindow ?? EventPickerWindow.defaultWindow(now: Date())
    }

    private var filteredEvents: [UpcomingEvent] {
        EventPickerFiltering.events(
            availableEvents,
            in: effectiveWindow,
            query: searchQuery
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Link a calendar event")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.secondaryText.swiftUIColor)
                Spacer()
                if bridge.isLoadingAvailableEvents {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                }
            }

            searchField

            HStack(spacing: 6) {
                windowButton("Load earlier", systemImage: "chevron.up") {
                    load(effectiveWindow.extendingEarlier())
                }

                Spacer(minLength: 4)

                Text(windowLabel(effectiveWindow))
                    .font(.system(size: 10.5))
                    .foregroundStyle(theme.tertiaryText.swiftUIColor)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)

                Spacer(minLength: 4)

                windowButton("Load later", systemImage: "chevron.down") {
                    load(effectiveWindow.extendingLater())
                }
            }

            Divider()
                .overlay(theme.hairline.swiftUIColor)

            eventList

            if isLinked {
                Divider()
                    .overlay(theme.hairline.swiftUIColor)

                Button {
                    bridge.unlinkEvent()
                    dismiss()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.tertiaryText.swiftUIColor)
                            .frame(width: 13)
                        Text("No event")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.secondaryText.swiftUIColor)
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 340, height: 390, alignment: .top)
        .padding(10)
        .background(theme.panelFill.swiftUIColor)
        .onAppear {
            let window = bridge.availableEventWindow ?? EventPickerWindow.defaultWindow(now: Date())
            loadedWindow = window
            if bridge.availableEventWindow == nil {
                bridge.requestCalendarEvents(window: window)
            }
        }
        .onChange(of: bridge.availableEventWindow) { newWindow in
            if let newWindow {
                loadedWindow = newWindow
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(theme.tertiaryText.swiftUIColor)
            TextField("Search events", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(theme.primaryText.swiftUIColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 7).fill(theme.fieldFill.swiftUIColor))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(theme.fieldBorder.swiftUIColor, lineWidth: 1))
    }

    private var eventList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                if let error = bridge.availableEventsError {
                    emptyMessage(error)
                } else if filteredEvents.isEmpty {
                    emptyMessage(searchQuery.isEmpty ? "No events in this range" : "No matching events")
                } else {
                    ForEach(filteredEvents, id: \.id) { event in
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
                            EventPickerRow(event: event, theme: theme)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func emptyMessage(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 12))
            .foregroundStyle(theme.tertiaryText.swiftUIColor)
            .frame(maxWidth: .infinity, minHeight: 180)
    }

    private func windowButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 9, weight: .semibold))
                Text(title)
                    .font(.system(size: 10.5, weight: .medium))
            }
            .foregroundStyle(theme.secondaryText.swiftUIColor)
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6).fill(theme.hoverFill.swiftUIColor))
        }
        .buttonStyle(.plain)
    }

    private func load(_ window: EventPickerWindow) {
        loadedWindow = window
        bridge.requestCalendarEvents(window: window)
    }

    private func windowLabel(_ window: EventPickerWindow) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let inclusiveEnd = window.end.addingTimeInterval(-1)
        return "\(formatter.string(from: window.start)) - \(formatter.string(from: inclusiveEnd))"
    }
}

private struct EventPickerRow: View {
    let event: UpcomingEvent
    let theme: ThemeColors

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            VStack(spacing: 1) {
                Text(dayText(event.start))
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(theme.secondaryText.swiftUIColor)
                Text(dateText(event.start))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(theme.primaryText.swiftUIColor)
            }
            .frame(width: 42, height: 36)
            .background(RoundedRectangle(cornerRadius: 6).fill(theme.chipFill.swiftUIColor))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(theme.hairline.swiftUIColor, lineWidth: 1))

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(event.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.primaryText.swiftUIColor)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(timeText(start: event.start, end: event.end))
                        .font(.system(size: 10.5, design: .monospaced).monospacedDigit())
                        .foregroundStyle(theme.tertiaryText.swiftUIColor)
                }

                if !event.participants.isEmpty || event.locationText != nil {
                    Text(detailText)
                        .font(.system(size: 10.5))
                        .foregroundStyle(theme.tertiaryText.swiftUIColor)
                        .lineLimit(1)
                }
            }
            .padding(.top, 1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.clear))
    }

    private var detailText: String {
        let people = event.participants.prefix(2).map(\.name).joined(separator: ", ")
        if let location = event.locationText, !location.isEmpty, !people.isEmpty {
            return "\(people) · \(location)"
        }
        return people.isEmpty ? (event.locationText ?? "") : people
    }

    private func dayText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }

    private func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    private func timeText(start: Date, end: Date?) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        guard let end else { return formatter.string(from: start) }
        return "\(formatter.string(from: start))-\(formatter.string(from: end))"
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
        Button {
            showDatePicker.toggle()
        } label: {
            HStack(spacing: 6) {
                Text(dateLabel)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.primaryText.swiftUIColor.opacity(0.85))
                    .underline(isHoveringDate, color: theme.hairline.swiftUIColor)

                Text("·")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.tertiaryText.swiftUIColor)

                Text(timeLabel)
                    .font(.system(size: 12, design: .monospaced).monospacedDigit())
                    .foregroundStyle(theme.secondaryText.swiftUIColor)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHoveringDate ? theme.hoverFill.swiftUIColor : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHoveringDate = $0 }
        .popover(isPresented: $showDatePicker, arrowEdge: .bottom) {
            DatePickerPopover(date: date, end: end, bridge: bridge, theme: theme) {
                showDatePicker = false
            }
        }
    }
}

private struct DatePickerPopover: View {
    let date: Date
    let end: Date?
    @ObservedObject var bridge: FrontmatterPresenterBridge
    let theme: ThemeColors
    let dismiss: () -> Void
    @State private var selectedDate: Date
    @State private var selectedEnd: Date
    @State private var hasEnd: Bool
    @State private var startTimeText: String
    @State private var endTimeText: String

    init(date: Date, end: Date?, bridge: FrontmatterPresenterBridge, theme: ThemeColors, dismiss: @escaping () -> Void) {
        self.date = date
        self.end = end
        self.bridge = bridge
        self.theme = theme
        self.dismiss = dismiss
        self._selectedDate = State(initialValue: date)
        self._selectedEnd = State(initialValue: end ?? Calendar.current.date(byAdding: .hour, value: 1, to: date) ?? date)
        self._hasEnd = State(initialValue: end != nil)
        self._startTimeText = State(initialValue: Self.timeFormatter.string(from: date))
        self._endTimeText = State(initialValue: Self.timeFormatter.string(from: end ?? Calendar.current.date(byAdding: .hour, value: 1, to: date) ?? date))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Date & time")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.secondaryText.swiftUIColor)

            VStack(spacing: 8) {
                DateTimeEditRow(
                    label: "Start",
                    date: $selectedDate,
                    timeText: $startTimeText,
                    theme: theme,
                    isEnabled: true,
                    onMove: { moveStart(minutes: $0) },
                    onCommitTime: { applyStartTimeText() }
                )

                DateTimeEditRow(
                    label: "End",
                    date: $selectedEnd,
                    timeText: $endTimeText,
                    theme: theme,
                    isEnabled: hasEnd,
                    onMove: { moveEnd(minutes: $0) },
                    onCommitTime: { applyEndTimeText() }
                )
            }
            .onChange(of: selectedDate) { newStart in
                guard hasEnd, selectedEnd < newStart else { return }
                selectedEnd = Calendar.current.date(byAdding: .hour, value: 1, to: newStart) ?? newStart
                endTimeText = Self.timeFormatter.string(from: selectedEnd)
            }

            HStack(spacing: 6) {
                Toggle("", isOn: $hasEnd)
                    .labelsHidden()
                    .toggleStyle(.checkbox)
                Text("Use end time")
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.secondaryText.swiftUIColor)
                Spacer()
                if hasEnd {
                    Button("Clear end") {
                        hasEnd = false
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.tertiaryText.swiftUIColor)
                }
            }
            .padding(.horizontal, 8)

            if hasEnd && selectedEnd < selectedDate {
                Text("End must be after start")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.red.opacity(0.85))
                    .padding(.horizontal, 8)
            }

            HStack(spacing: 8) {
                Text(summaryLabel)
                    .font(.system(size: 11, design: .monospaced).monospacedDigit())
                    .foregroundStyle(theme.tertiaryText.swiftUIColor)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 7).fill(theme.fieldFill.swiftUIColor))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(theme.fieldBorder.swiftUIColor, lineWidth: 1))

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(theme.secondaryText.swiftUIColor)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)

                Button {
                    applyStartTimeText()
                    if hasEnd { applyEndTimeText() }
                    bridge.setDate(selectedDate, end: hasEnd ? selectedEnd : nil)
                    dismiss()
                } label: {
                    Text("Done")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(canSave ? theme.accent.swiftUIColor : theme.tertiaryText.swiftUIColor)
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canSave)
            }
        }
        .frame(width: 390)
        .padding(12)
        .background(theme.panelFill.swiftUIColor)
    }

    private var canSave: Bool {
        !hasEnd || selectedEnd >= selectedDate
    }

    private var summaryLabel: String {
        let day = Self.dayFormatter.string(from: selectedDate)
        let time = Self.timeFormatter.string(from: selectedDate)
        guard hasEnd else { return "\(day) \(time)" }
        return "\(day) \(time) - \(Self.dayFormatter.string(from: selectedEnd)) \(Self.timeFormatter.string(from: selectedEnd))"
    }

    private func moveStart(minutes: Int) {
        selectedDate = Calendar.current.date(byAdding: .minute, value: minutes, to: selectedDate) ?? selectedDate
        startTimeText = Self.timeFormatter.string(from: selectedDate)
    }

    private func moveEnd(minutes: Int) {
        selectedEnd = Calendar.current.date(byAdding: .minute, value: minutes, to: selectedEnd) ?? selectedEnd
        endTimeText = Self.timeFormatter.string(from: selectedEnd)
    }

    private func applyStartTimeText() {
        if let adjusted = dateByApplyingTimeText(startTimeText, to: selectedDate) {
            selectedDate = adjusted
            startTimeText = Self.timeFormatter.string(from: adjusted)
        }
    }

    private func applyEndTimeText() {
        if let adjusted = dateByApplyingTimeText(endTimeText, to: selectedEnd) {
            selectedEnd = adjusted
            endTimeText = Self.timeFormatter.string(from: adjusted)
        }
    }

    private func dateByApplyingTimeText(_ text: String, to date: Date) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let pieces = trimmed.split(separator: ":")
        guard pieces.count == 2,
              let hour = Int(pieces[0]),
              let minute = Int(pieces[1]),
              (0...23).contains(hour),
              (0...59).contains(minute) else { return nil }
        return Calendar.current.date(
            bySettingHour: hour,
            minute: minute,
            second: 0,
            of: date
        )
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
}

private struct DateTimeEditRow: View {
    let label: String
    @Binding var date: Date
    @Binding var timeText: String
    let theme: ThemeColors
    var isEnabled: Bool = true
    let onMove: (Int) -> Void
    let onCommitTime: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(theme.tertiaryText.swiftUIColor)
                .frame(width: 34, alignment: .leading)

            DatePicker(
                "",
                selection: $date,
                displayedComponents: [.date, .hourAndMinute]
            )
            .labelsHidden()
            .datePickerStyle(.field)
            .controlSize(.small)
            .disabled(!isEnabled)
            .opacity(isEnabled ? 1 : 0.45)
            .frame(width: 160, alignment: .leading)
            .tint(theme.accent.swiftUIColor)

            TextField("HH:mm", text: $timeText)
                .textFieldStyle(.plain)
                .font(.system(size: 11, design: .monospaced).monospacedDigit())
                .foregroundStyle(theme.primaryText.swiftUIColor)
                .frame(width: 42)
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 5).fill(theme.panelFill.swiftUIColor))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(theme.fieldBorder.swiftUIColor, lineWidth: 1))
                .disabled(!isEnabled)
                .opacity(isEnabled ? 1 : 0.45)
                .onSubmit(onCommitTime)

            Button {
                onMove(-5)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 9, weight: .medium))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.secondaryText.swiftUIColor)
            .disabled(!isEnabled)
            .background(RoundedRectangle(cornerRadius: 6).fill(theme.hoverFill.swiftUIColor))

            Button {
                onMove(5)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .medium))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.secondaryText.swiftUIColor)
            .disabled(!isEnabled)
            .background(RoundedRectangle(cornerRadius: 6).fill(theme.hoverFill.swiftUIColor))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(theme.fieldFill.swiftUIColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(theme.fieldBorder.swiftUIColor, lineWidth: 1)
        )
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
    let onRecordPillIdleTap: (() -> Void)?
    let theme: ThemeColors

    @StateObject private var playback = AudioPlaybackController()

    var body: some View {
        if let url = bridge.audioFileURL {
            AudioPlayerView(
                state: playback.state,
                onTogglePlay: { playback.togglePlay() },
                onSeek: { playback.seek(to: $0) }
            )
            .environment(\.themeColors, theme)
            .frame(maxWidth: 180)
            .onAppear { playback.load(url: url) }
            .onChange(of: bridge.audioFileURL) { playback.load(url: $0) }
        } else {
            RecordPillView(
                machine: machine,
                pillState: pillState,
                onIdleTapOverride: onRecordPillIdleTap
            )
                .environment(\.themeColors, theme)
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

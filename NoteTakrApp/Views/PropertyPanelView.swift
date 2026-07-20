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
        .accessibilityIdentifier("calendarEventPickerButton")
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
    @State private var pendingConfirmation: EventLinkConfirmation?
    @State private var selectedEventID: String?
    @State private var hoveredEventID: String?
    @State private var eventRowFrames: [String: CGRect] = [:]
    @State private var eventListHeight: CGFloat = 0
    @FocusState private var searchFocused: Bool

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

    private var filteredEventsSignature: String {
        filteredEvents.map { "\($0.id):\($0.start.timeIntervalSince1970)" }.joined(separator: "|")
    }

    var body: some View {
        ScrollViewReader { proxy in
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

                searchField(proxy: proxy)

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
            .frame(width: 360, height: 420, alignment: .top)
            .padding(10)
            .background(theme.background.swiftUIColor)
            .onAppear {
                let window = bridge.availableEventWindow ?? EventPickerWindow.defaultWindow(now: Date())
                loadedWindow = window
                if bridge.availableEventWindow == nil {
                    bridge.requestCalendarEvents(window: window)
                }
                searchFocused = true
                focusCurrentEvent(proxy: proxy)
            }
            .onChange(of: bridge.availableEventWindow) { _, newWindow in
                if let newWindow {
                    loadedWindow = newWindow
                }
            }
            .onChange(of: filteredEventsSignature) { _, _ in
                focusCurrentEvent(proxy: proxy)
            }
            .onPreferenceChange(EventPickerRowFramePreferenceKey.self) { eventRowFrames = $0 }
            .onPreferenceChange(EventPickerListHeightPreferenceKey.self) { eventListHeight = $0 }
            .overlay {
                if let pendingConfirmation {
                    EventSwitchConfirmationOverlay(
                        confirmation: pendingConfirmation,
                        theme: theme,
                        cancel: { self.pendingConfirmation = nil },
                        confirm: {
                            applyEvent(pendingConfirmation.event)
                            self.pendingConfirmation = nil
                        }
                    )
                }
            }
        }
    }

    private func searchField(proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(theme.tertiaryText.swiftUIColor)
            TextField("Search events", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(theme.primaryText.swiftUIColor)
                .focused($searchFocused)
                .onKeyPress(.upArrow) {
                    moveSelection(by: -1, proxy: proxy)
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    moveSelection(by: 1, proxy: proxy)
                    return .handled
                }
                .onKeyPress(.return) {
                    activateSelectedEvent()
                    return .handled
                }
                .accessibilityIdentifier("eventPickerSearchField")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 7).fill(theme.fieldFill.swiftUIColor))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(theme.fieldBorder.swiftUIColor, lineWidth: 1))
    }

    private var eventList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 1) {
                if let error = bridge.availableEventsError {
                    emptyMessage(error)
                } else if filteredEvents.isEmpty {
                    emptyMessage(searchQuery.isEmpty ? "No events in this range" : "No matching events")
                } else {
                    ForEach(filteredEvents, id: \.id) { event in
                        let isSelected = selectedEventID == event.id
                        let isHovering = hoveredEventID == event.id && !isSelected
                        Button {
                            selectEvent(event)
                        } label: {
                            EventPickerRow(
                                event: event,
                                dotState: EventPickerSelection.dotState(for: event, now: Date()),
                                isSelected: isSelected,
                                isHovering: isHovering,
                                theme: theme
                            )
                        }
                        .buttonStyle(.plain)
                        .id(event.id)
                        .onHover { hovering in
                            hoveredEventID = hovering ? event.id : (hoveredEventID == event.id ? nil : hoveredEventID)
                        }
                        .background(
                            GeometryReader { geometry in
                                Color.clear.preference(
                                    key: EventPickerRowFramePreferenceKey.self,
                                    value: [event.id: geometry.frame(in: .named("eventPickerViewport"))]
                                )
                            }
                        )
                        .accessibilityIdentifier("eventPickerRow_\(event.id)")
                        .accessibilityValue(isSelected ? "Focused" : "")
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .coordinateSpace(name: "eventPickerViewport")
        .background(
            GeometryReader { geometry in
                Color.clear.preference(
                    key: EventPickerListHeightPreferenceKey.self,
                    value: geometry.size.height
                )
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("eventPickerList")
    }

    private func focusCurrentEvent(proxy: ScrollViewProxy) {
        guard let index = EventPickerSelection.focusedIndex(in: filteredEvents, now: Date()) else {
            selectedEventID = nil
            return
        }
        let id = filteredEvents[index].id
        selectedEventID = id
        DispatchQueue.main.async {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                proxy.scrollTo(id, anchor: .top)
            }
        }
    }

    private func moveSelection(by offset: Int, proxy: ScrollViewProxy) {
        guard !filteredEvents.isEmpty else { return }
        let current = selectedEventID.flatMap { id in
            filteredEvents.firstIndex(where: { $0.id == id })
        } ?? EventPickerSelection.focusedIndex(in: filteredEvents, now: Date()) ?? 0
        let next = min(max(current + offset, filteredEvents.startIndex), filteredEvents.index(before: filteredEvents.endIndex))
        let id = filteredEvents[next].id
        selectedEventID = id

        DispatchQueue.main.async {
            guard let frame = eventRowFrames[id] else {
                proxy.scrollTo(id, anchor: offset > 0 ? .bottom : .top)
                return
            }
            switch EdgeAwareScrollPolicy.revealEdge(
                rowMinY: Double(frame.minY),
                rowMaxY: Double(frame.maxY),
                viewportHeight: Double(eventListHeight)
            ) {
            case .top:
                withAnimation(.easeOut(duration: 0.1)) { proxy.scrollTo(id, anchor: .top) }
            case .bottom:
                withAnimation(.easeOut(duration: 0.1)) { proxy.scrollTo(id, anchor: .bottom) }
            case nil:
                break
            }
        }
    }

    private func activateSelectedEvent() {
        guard let selectedEventID,
              let event = filteredEvents.first(where: { $0.id == selectedEventID }) else { return }
        selectEvent(event)
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

    private func selectEvent(_ event: UpcomingEvent) {
        let changes = confirmationChanges(for: event)
        if changes.isEmpty {
            applyEvent(event)
        } else {
            pendingConfirmation = EventLinkConfirmation(event: event, changes: changes)
        }
    }

    private func applyEvent(_ event: UpcomingEvent) {
        bridge.linkCalendarEvent(
            id: event.id,
            title: event.title,
            attendees: event.participants,
            startDate: event.start,
            endDate: event.end,
            locationText: event.locationText,
            meetingLink: event.meetingLink
        )
        dismiss()
    }

    private func confirmationChanges(for event: UpcomingEvent) -> [EventLinkChange] {
        var changes: [EventLinkChange] = []
        let isSwitchingLinkedEvent = bridge.noteCalendarEvent != nil && bridge.noteCalendarEvent != event.id

        if isSwitchingLinkedEvent,
           !valuesMatch(bridge.noteTitle, event.title) {
            changes.append(EventLinkChange(field: "Title", before: bridge.noteTitle, after: event.title))
        }

        if isSwitchingLinkedEvent,
           let currentStart = bridge.noteDate,
           !datesMatch(currentStart, event.start) || !optionalDatesMatch(bridge.noteEnd, event.end) {
            changes.append(EventLinkChange(
                field: "Time",
                before: timeRangeText(start: currentStart, end: bridge.noteEnd),
                after: timeRangeText(start: event.start, end: event.end)
            ))
        }

        let currentLocation = normalizedText(bridge.noteLocationText)
        let eventLocation = normalizedText(event.locationText)
        if currentLocation != nil, currentLocation != eventLocation {
            changes.append(EventLinkChange(
                field: "Location",
                before: currentLocation ?? "No location",
                after: eventLocation ?? "No location"
            ))
        }

        let currentLink = normalizedText(bridge.noteMeetingLink)
        let eventLink = normalizedText(event.meetingLink)
        if currentLink != nil, currentLink != eventLink {
            changes.append(EventLinkChange(
                field: "Link",
                before: currentLink ?? "No link",
                after: eventLink ?? "No link"
            ))
        }

        let currentPeople = bridge.participants
        let eventPeople = event.participants
        if !currentPeople.isEmpty, !participantsMatch(currentPeople, eventPeople) {
            changes.append(EventLinkChange(
                field: "People",
                before: peopleText(currentPeople),
                after: eventPeople.isEmpty ? "No people" : peopleText(eventPeople)
            ))
        }

        return Array(changes.prefix(5))
    }

    private func windowLabel(_ window: EventPickerWindow) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let inclusiveEnd = window.end.addingTimeInterval(-1)
        return "\(formatter.string(from: window.start)) - \(formatter.string(from: inclusiveEnd))"
    }

    private func normalizedText(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private func valuesMatch(_ lhs: String, _ rhs: String) -> Bool {
        normalizedText(lhs) == normalizedText(rhs)
    }

    private func datesMatch(_ lhs: Date, _ rhs: Date) -> Bool {
        abs(lhs.timeIntervalSince(rhs)) < 1
    }

    private func optionalDatesMatch(_ lhs: Date?, _ rhs: Date?) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none):
            return true
        case (.some(let lhs), .some(let rhs)):
            return datesMatch(lhs, rhs)
        default:
            return false
        }
    }

    private func participantsMatch(_ lhs: [Participant], _ rhs: [Participant]) -> Bool {
        normalizedParticipantKeys(lhs) == normalizedParticipantKeys(rhs)
    }

    private func normalizedParticipantKeys(_ participants: [Participant]) -> [String] {
        participants
            .map { participant in
                let email = normalizedText(participant.email)
                let name = Participant.displayName(name: participant.name, email: email)
                return (email ?? name).lowercased()
            }
            .sorted()
    }

    private func peopleText(_ participants: [Participant]) -> String {
        participants
            .prefix(3)
            .map { $0.displayName }
            .joined(separator: ", ")
    }

    private func timeRangeText(start: Date, end: Date?) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, HH:mm"
        let startText = formatter.string(from: start)
        guard let end else { return startText }
        return "\(startText)-\(formatter.string(from: end))"
    }
}

private struct EventLinkConfirmation: Identifiable {
    let id = UUID()
    let event: UpcomingEvent
    let changes: [EventLinkChange]
}

private struct EventLinkChange: Identifiable {
    let id = UUID()
    let field: String
    let before: String
    let after: String
}

private struct EventSwitchConfirmationOverlay: View {
    let confirmation: EventLinkConfirmation
    let theme: ThemeColors
    let cancel: () -> Void
    let confirm: () -> Void

    var body: some View {
        ZStack {
            theme.background.swiftUIColor.opacity(0.55)

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.accent.swiftUIColor)
                        .frame(width: 20, height: 20)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Update note details?")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(theme.primaryText.swiftUIColor)
                        Text(confirmation.event.title)
                            .font(.system(size: 11.5))
                            .foregroundStyle(theme.tertiaryText.swiftUIColor)
                            .lineLimit(1)
                    }
                }

                VStack(spacing: 6) {
                    ForEach(confirmation.changes) { change in
                        HStack(alignment: .top, spacing: 8) {
                            Text(change.field)
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(theme.tertiaryText.swiftUIColor)
                                .frame(width: 48, alignment: .leading)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(change.before)
                                    .font(.system(size: 11))
                                    .foregroundStyle(theme.secondaryText.swiftUIColor)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.right")
                                        .font(.system(size: 8, weight: .semibold))
                                    Text(change.after)
                                        .font(.system(size: 11, weight: .medium))
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                .foregroundStyle(theme.primaryText.swiftUIColor)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 7).fill(theme.fieldFill.swiftUIColor))
                    }
                }

                HStack(spacing: 8) {
                    Spacer()
                    Button("Cancel", action: cancel)
                        .buttonStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.secondaryText.swiftUIColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)

                    Button(action: confirm) {
                        Text("Update")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: 7).fill(theme.accent.swiftUIColor))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
            .frame(width: 300)
            .background(theme.panelFill.swiftUIColor)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.hairline.swiftUIColor, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .shadow(color: Color.black.opacity(0.22), radius: 18, y: 10)
        }
        .transition(.opacity)
    }
}

private struct EventPickerRow: View {
    let event: UpcomingEvent
    let dotState: DotState
    let isSelected: Bool
    let isHovering: Bool
    let theme: ThemeColors

    var body: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(theme.elevatedFill.swiftUIColor)
                    .frame(width: 28, height: 28)
                Image(systemName: event.meetingLink == nil ? "calendar" : "video")
                    .font(.system(size: 12.5))
                    .foregroundStyle(theme.secondaryText.swiftUIColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Text(event.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(theme.primaryText.swiftUIColor)
                        .lineLimit(1)
                    if dotState == .current {
                        Text("NOW")
                            .font(.system(size: 9.5, weight: .bold))
                            .tracking(0.5)
                            .foregroundStyle(theme.accent.swiftUIColor)
                            .padding(.horizontal, 6)
                            .frame(height: 18)
                            .background(theme.accent.swiftUIColor.opacity(0.14))
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                            .overlay(RoundedRectangle(cornerRadius: 5)
                                .stroke(theme.accent.swiftUIColor.opacity(0.38), lineWidth: 1))
                    }
                }

                Text(subtitleText)
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.secondaryText.swiftUIColor)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 5) {
                Image(systemName: "link")
                    .font(.system(size: 10.5, weight: .semibold))
                Text("Link")
                    .font(.system(size: 11.5, weight: .medium))
            }
            .foregroundStyle(theme.accent.swiftUIColor)
            .padding(.horizontal, 9)
            .frame(height: 26)
            .background(theme.accent.swiftUIColor.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7)
                .stroke(theme.accent.swiftUIColor.opacity(0.4), lineWidth: 1))
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 54)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected
                      ? theme.accent.swiftUIColor.opacity(0.16)
                      : (isHovering ? theme.hoverFill.swiftUIColor : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? theme.accent.swiftUIColor.opacity(0.45) : Color.clear, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .animation(.easeOut(duration: 0.12), value: isSelected)
    }

    private var subtitleText: String {
        var pieces = [dateAndTimeText]
        let people = event.participants.prefix(2).map(\.name).joined(separator: ", ")
        if !people.isEmpty { pieces.append(people) }
        if let location = event.locationText, !location.isEmpty { pieces.append(location) }
        return pieces.joined(separator: " · ")
    }

    private var dateAndTimeText: String {
        let dayFormatter = DateFormatter()
        if Calendar.current.isDateInToday(event.start) {
            dayFormatter.dateFormat = "'Today'"
        } else if Calendar.current.isDateInTomorrow(event.start) {
            dayFormatter.dateFormat = "'Tomorrow'"
        } else {
            dayFormatter.dateFormat = "EEE, MMM d"
        }
        return "\(dayFormatter.string(from: event.start)), \(timeText(start: event.start, end: event.end))"
    }

    private func timeText(start: Date, end: Date?) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        guard let end else { return formatter.string(from: start) }
        return "\(formatter.string(from: start))-\(formatter.string(from: end))"
    }
}

private struct EventPickerRowFramePreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct EventPickerListHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
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
                    .foregroundStyle(theme.accent.swiftUIColor.opacity(0.85))
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

    @State private var menuParticipant: Participant? = nil
    @State private var showAddPopover = false
    @State private var newPersonName = ""
    @State private var newPersonEmail = ""

    var body: some View {
        HStack(spacing: 5) {
            if participants.isEmpty {
                Text("—")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.tertiaryText.swiftUIColor)
            } else {
                ForEach(participants.prefix(6), id: \.self) { participant in
                    participantCircle(participant)
                }
                if participants.count > 6 {
                    Text("+\(participants.count - 6)")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(theme.tertiaryText.swiftUIColor)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(theme.chipFill.swiftUIColor))
                }
            }

            Button {
                showAddPopover = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(theme.tertiaryText.swiftUIColor)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(theme.chipFill.swiftUIColor))
                    .overlay(Circle().stroke(theme.hairline.swiftUIColor.opacity(0.8), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("Add person")
            .popover(isPresented: $showAddPopover, arrowEdge: .bottom) {
                AddParticipantPopover(
                    name: $newPersonName,
                    email: $newPersonEmail,
                    theme: theme,
                    suggestions: { query in
                        bridge.participantSuggestions(
                            matching: query,
                            excluding: participants
                        )
                    },
                    cancel: {
                        newPersonName = ""
                        newPersonEmail = ""
                        showAddPopover = false
                    },
                    add: {
                        commitAdd()
                        showAddPopover = false
                    },
                    selectSuggestion: { entry in
                        bridge.addParticipant(entry.participant)
                        newPersonName = ""
                        newPersonEmail = ""
                        showAddPopover = false
                    }
                )
            }
        }
        .frame(minWidth: 116, alignment: .trailing)
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.environment["NOTETAKR_E2E_OPEN_PEOPLE_PICKER"] == "1" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    showAddPopover = true
                }
            }
            #endif
        }
    }

    @ViewBuilder
    private func participantCircle(_ participant: Participant) -> some View {
        let displayName = participant.displayName
        let initials = initials(for: displayName)

        Button {
            menuParticipant = participant
        } label: {
            ZStack {
                Circle()
                    .fill(theme.avatarFill.swiftUIColor)
                    .frame(width: 26, height: 26)
                Circle()
                    .stroke(theme.hairline.swiftUIColor.opacity(0.8), lineWidth: 1)
                    .frame(width: 26, height: 26)

                Text(initials)
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(theme.secondaryText.swiftUIColor)
            }
            .frame(width: 28, height: 28)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .popover(
            isPresented: Binding(
                get: { menuParticipant == participant },
                set: { if !$0 { menuParticipant = nil } }
            ),
            arrowEdge: .bottom
        ) {
            ParticipantMenu(
                participant: participant,
                personEntry: bridge.personEntry(for: participant),
                bridge: bridge,
                theme: theme,
                dismiss: { menuParticipant = nil }
            )
        }
        .help("\(displayName)\(participant.email.map { "\n\($0)" } ?? "")\nClick to manage")
    }

    private func initials(for name: String) -> String {
        let initials = name.split(separator: " ").prefix(2)
            .compactMap { $0.first.map { String($0).uppercased() } }
            .joined()
        return initials.isEmpty ? "?" : initials
    }

    private func commitAdd() {
        let trimmedName = newPersonName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = newPersonEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = trimmedEmail.isEmpty ? nil : trimmedEmail
        let name = Participant.displayName(
            name: trimmedName.isEmpty ? nil : trimmedName,
            email: email
        )

        if !name.isEmpty {
            bridge.addParticipant(name: name, email: email)
        }

        newPersonName = ""
        newPersonEmail = ""
    }
}

private struct AddParticipantPopover: View {
    @Binding var name: String
    @Binding var email: String
    let theme: ThemeColors
    let suggestions: (String) -> [PersonIndexEntry]
    let cancel: () -> Void
    let add: () -> Void
    let selectSuggestion: (PersonIndexEntry) -> Void

    @FocusState private var focusedField: Field?

    private enum Field {
        case name
        case email
    }

    private var canAdd: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var suggestionQuery: String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty { return trimmedName }
        return email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var visibleSuggestions: [PersonIndexEntry] {
        suggestions(suggestionQuery)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.accent.swiftUIColor)
                Text("Add person")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(theme.primaryText.swiftUIColor)
            }

            VStack(spacing: 8) {
                personTextField("Name", text: $name, focus: .name)
                personTextField("Email", text: $email, focus: .email)
            }

            if !visibleSuggestions.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text(suggestionQuery.isEmpty ? "Recent people" : "Suggestions")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(theme.tertiaryText.swiftUIColor)

                    VStack(spacing: 3) {
                        ForEach(visibleSuggestions) { entry in
                            Button {
                                selectSuggestion(entry)
                            } label: {
                                PersonSuggestionRow(entry: entry, theme: theme)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                Spacer()
                Button("Cancel", action: cancel)
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.secondaryText.swiftUIColor)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)

                Button(action: add) {
                    Text("Add")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(canAdd ? theme.accent.swiftUIColor : theme.tertiaryText.swiftUIColor)
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canAdd)
            }
        }
        .frame(width: 286)
        .padding(12)
        .background(theme.panelFill.swiftUIColor)
        .onAppear { focusedField = .name }
    }

    @ViewBuilder
    private func personTextField(_ placeholder: String, text: Binding<String>, focus: Field) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(theme.primaryText.swiftUIColor)
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 7).fill(theme.fieldFill.swiftUIColor))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(theme.fieldBorder.swiftUIColor, lineWidth: 1))
            .focused($focusedField, equals: focus)
            .onSubmit(add)
    }
}

private struct PersonSuggestionRow: View {
    let entry: PersonIndexEntry
    let theme: ThemeColors

    var body: some View {
        HStack(spacing: 8) {
            Text(initials(for: entry.displayName))
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(theme.secondaryText.swiftUIColor)
                .frame(width: 24, height: 24)
                .background(Circle().fill(theme.avatarFill.swiftUIColor))
                .overlay(Circle().stroke(theme.hairline.swiftUIColor.opacity(0.9), lineWidth: 1))

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.primaryText.swiftUIColor)
                    .lineLimit(1)
                Text(detailText)
                    .font(.system(size: 10.5))
                    .foregroundStyle(theme.tertiaryText.swiftUIColor)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 6)

            Image(systemName: "plus")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(theme.tertiaryText.swiftUIColor)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .background(RoundedRectangle(cornerRadius: 7).fill(theme.hoverFill.swiftUIColor))
    }

    private var detailText: String {
        var pieces: [String] = []
        if entry.noteCount > 0 {
            pieces.append(entry.noteCount == 1 ? "1 past note" : "\(entry.noteCount) past notes")
        }
        if entry.calendarEventCount > 0 {
            pieces.append(entry.calendarEventCount == 1 ? "calendar attendee" : "\(entry.calendarEventCount) calendar events")
        }
        if let email = entry.participant.email, !email.isEmpty {
            pieces.append(email)
        }
        return pieces.isEmpty ? "Local person" : pieces.joined(separator: " · ")
    }

    private func initials(for name: String) -> String {
        let initials = name.split(separator: " ").prefix(2)
            .compactMap { $0.first.map { String($0).uppercased() } }
            .joined()
        return initials.isEmpty ? "?" : initials
    }
}

private struct ParticipantMenu: View {
    let participant: Participant
    let personEntry: PersonIndexEntry?
    @ObservedObject var bridge: FrontmatterPresenterBridge
    let theme: ThemeColors
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Text(initials(for: participant.displayName))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.secondaryText.swiftUIColor)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(theme.avatarFill.swiftUIColor))
                    .overlay(Circle().stroke(theme.hairline.swiftUIColor.opacity(0.9), lineWidth: 1))

                VStack(alignment: .leading, spacing: 3) {
                    Text(participant.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.primaryText.swiftUIColor)
                        .lineLimit(1)
                    Text(participant.email ?? "No email")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.tertiaryText.swiftUIColor)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            if showsInferredNameHint {
                Label("Name inferred from email", systemImage: "sparkles")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.tertiaryText.swiftUIColor)
                    .labelStyle(.titleAndIcon)
            }

            if let personEntry {
                VStack(alignment: .leading, spacing: 4) {
                    if personEntry.noteCount > 0 {
                        Label(
                            personEntry.noteCount == 1 ? "1 past note" : "\(personEntry.noteCount) past notes",
                            systemImage: "clock.arrow.circlepath"
                        )
                    }
                    if personEntry.calendarEventCount > 0 {
                        Label(
                            personEntry.calendarEventCount == 1 ? "Seen in calendar" : "\(personEntry.calendarEventCount) calendar events",
                            systemImage: "calendar"
                        )
                    }
                    if let crm = participant.crm, !crm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Label(crm, systemImage: "link")
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(theme.tertiaryText.swiftUIColor)
                .labelStyle(.titleAndIcon)
            }

            Divider().overlay(theme.hairline.swiftUIColor)

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
                .foregroundStyle(theme.destructive.swiftUIColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
                .background(RoundedRectangle(cornerRadius: 7).fill(theme.hoverFill.swiftUIColor))
            }
            .buttonStyle(.plain)
        }
        .frame(width: 240)
        .padding(12)
        .background(theme.panelFill.swiftUIColor)
    }

    private var showsInferredNameHint: Bool {
        guard let email = participant.email,
              let inferred = Participant.inferredName(fromEmail: email) else {
            return false
        }
        return participant.name.caseInsensitiveCompare(inferred) == .orderedSame
    }

    private func initials(for name: String) -> String {
        let initials = name.split(separator: " ").prefix(2)
            .compactMap { $0.first.map { String($0).uppercased() } }
            .joined()
        return initials.isEmpty ? "?" : initials
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
    private let fieldWidth: CGFloat = 190

    var body: some View {
        if isEditing {
            TextField(placeholder, text: $editText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(theme.primaryText.swiftUIColor)
                .multilineTextAlignment(.trailing)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .frame(width: fieldWidth, alignment: .trailing)
                .background(RoundedRectangle(cornerRadius: 6).fill(theme.fieldFill.swiftUIColor))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(theme.fieldBorder.swiftUIColor, lineWidth: 1))
                .focused($focused)
                .onSubmit { commit() }
                .onExitCommand { cancel() }
                .onAppear {
                    editText = value
                    DispatchQueue.main.async {
                        focused = true
                    }
                }
        } else {
            Text(display)
                .font(.system(size: 12))
                .foregroundStyle(
                    isEmpty
                        ? theme.tertiaryText.swiftUIColor
                        : theme.primaryText.swiftUIColor.opacity(0.85)
                )
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .frame(width: fieldWidth, alignment: .trailing)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHovering ? theme.hoverFill.swiftUIColor : Color.clear)
                )
                .underline(isHovering, color: theme.hairline.swiftUIColor)
                .contentShape(Rectangle())
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
                Text(bridge.isRecording
                     ? "In-person meetings are mic-only. Changing this now updates the active audio sources immediately."
                     : "In-person meetings are mic-only — NoteTakr skips system-audio capture.")
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

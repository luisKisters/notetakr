import SwiftUI
import NoteTakrKit

// MARK: - SwitcherOverlayView

/// Calendar-first command palette shown over the editor when Cmd-K is pressed.
/// Dark and light appearances use solid surfaces; event linking stays in the
/// meeting UI, so switcher actions are only Create, Open, or Delete.
struct SwitcherOverlayView: View {
    @ObservedObject var bridge: SwitcherBridge
    let appearance: Appearance
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var searchFocused: Bool
    @State private var hoveredIndex: Int?
    @State private var initialScrollApplied = false
    @State private var rowListReady = false
    @State private var suppressNextSelectionScroll = false

    private var paletteColors: ThemeColors {
        SwitcherOverlayPalette.colors(for: appearance, colorScheme: colorScheme)
    }

    private var paletteBackground: Color {
        paletteColors.background.swiftUIColor
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
                .padding(.horizontal, 18)
                .padding(.top, 42)
                .padding(.bottom, 10)

            rowList

            hintsFooter
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(paletteBackground.ignoresSafeArea())
        .onAppear { focusSearchField() }
        .background(keyboardButtons)
        .accessibilityIdentifier("switcherOverlay")
    }

    // MARK: - Search

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(paletteColors.tertiaryText.swiftUIColor)
                .frame(width: 18)

            TextField("Search meetings…", text: $bridge.searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundColor(paletteColors.primaryText.swiftUIColor)
                .focused($searchFocused)
                .onKeyPress(.upArrow) { bridge.moveUp(); return .handled }
                .onKeyPress(.downArrow) { bridge.moveDown(); return .handled }
                .accessibilityIdentifier("switcherSearchField")

            kbdBadge("⌘K")
        }
        .frame(height: 42)
        .padding(.horizontal, 13)
        .background(paletteColors.fieldFill.swiftUIColor)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(searchFocused ? paletteColors.accent.swiftUIColor.opacity(0.45)
                        : paletteColors.fieldBorder.swiftUIColor, lineWidth: 1)
        )
    }

    // MARK: - List

    private var rowList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(bridge.groups, id: \.switcherOverlayID) { group in
                        rowGroupSection(group: group)
                    }
                    if bridge.groups.isEmpty {
                        Text("No meetings match this search.")
                            .font(.system(size: 12))
                            .foregroundColor(paletteColors.tertiaryText.swiftUIColor)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 28)
                            .padding(.horizontal, 20)
                            .multilineTextAlignment(.center)
                            .accessibilityIdentifier("switcherEmptyState")
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }
            .accessibilityIdentifier("switcherEventList")
            .background(paletteBackground)
            .mask(rowListFadeMask)
            .opacity(rowListReady ? 1 : 0)
            .onAppear {
                applyInitialScroll(proxy: proxy)
            }
            .onChange(of: groupsSignature) { _, _ in
                applyInitialScroll(proxy: proxy)
            }
            .onChange(of: bridge.selectedIndex) { _, idx in
                if suppressNextSelectionScroll {
                    suppressNextSelectionScroll = false
                    return
                }
                guard let item = bridge.viewModel.selectedItem else { return }
                withAnimation(.easeOut(duration: 0.1)) {
                    proxy.scrollTo(rowID(flatIndex: idx, item: item), anchor: .center)
                }
            }
        }
    }

    private var rowListFadeMask: some View {
        VStack(spacing: 0) {
            Color.black.frame(height: 34)
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.00),
                    .init(color: .black, location: 1.00),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 24)
            Color.black
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0.00),
                    .init(color: .clear, location: 1.00),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 34)
        }
    }

    private var groupsSignature: String {
        bridge.groups.map(\.switcherOverlayID).joined(separator: "||")
    }

    private func applyInitialScroll(proxy: ScrollViewProxy) {
        guard !initialScrollApplied else {
            rowListReady = true
            return
        }
        initialScrollApplied = true
        rowListReady = false

        guard bridge.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let target = initialViewportTargetID()
        else {
            rowListReady = true
            return
        }

        DispatchQueue.main.async {
            scrollToInitialTarget(target, proxy: proxy)
            DispatchQueue.main.async {
                scrollToInitialTarget(target, proxy: proxy)
                rowListReady = true
            }
        }
    }

    private func scrollToInitialTarget(_ target: String, proxy: ScrollViewProxy) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            proxy.scrollTo(target, anchor: UnitPoint(x: 0.5, y: 0.70))
        }
    }

    private func initialViewportTargetID() -> String? {
        guard let upcoming = bridge.groups.first,
              upcoming.label == "Upcoming",
              upcoming.items.count >= 3
        else { return nil }

        if bridge.groups.count > 1, let firstItemAfterUpcoming = bridge.groups[1].items.first {
            return rowID(flatIndex: upcoming.items.count, item: firstItemAfterUpcoming)
        }

        let targetIndex = max(0, upcoming.items.count - 2)
        return rowID(flatIndex: targetIndex, item: upcoming.items[targetIndex])
    }

    @ViewBuilder
    private func rowGroupSection(group: SwitcherGroup) -> some View {
        Section {
            ForEach(Array(group.items.enumerated()), id: \.element.switcherOverlayID) { offset, item in
                let flatIdx = flatIndex(group: group, itemOffset: offset)
                twoLineRow(item: item, flatIndex: flatIdx)
                    .id(rowID(flatIndex: flatIdx, item: item))
            }
        } header: {
            Text(group.label.uppercased())
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(paletteColors.tertiaryText.swiftUIColor)
                .tracking(0.9)
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                .padding(.horizontal, 6)
                .background(paletteBackground)
                .zIndex(2)
                .accessibilityIdentifier("switcherSection_\(group.label)")
        }
        .id(group.switcherOverlayID)
    }

    @ViewBuilder
    private func twoLineRow(item: SwitcherItem, flatIndex: Int) -> some View {
        let isSelected = bridge.selectedIndex == flatIndex
        let isHovering = !isSelected && hoveredIndex == flatIndex
        let showDelete = (hoveredIndex == flatIndex || isSelected) && noteID(for: item) != nil

        rowCard(item: item, isSelected: isSelected, isHovering: isHovering, showDelete: showDelete)
            .padding(.bottom, 1)
            .contentShape(RoundedRectangle(cornerRadius: 11))
            .onTapGesture { tap(item: item) }
            .onHover { isHov in
                if isHov {
                    hoveredIndex = flatIndex
                    if bridge.selectedIndex != flatIndex {
                        suppressNextSelectionScroll = true
                    }
                    bridge.selectFromHover(index: flatIndex)
                } else if hoveredIndex == flatIndex {
                    hoveredIndex = nil
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("switcherRow_\(item.switcherOverlayID)")
    }

    @ViewBuilder
    private func rowCard(
        item: SwitcherItem,
        isSelected: Bool,
        isHovering: Bool,
        showDelete: Bool
    ) -> some View {
        HStack(spacing: 10) {
            timelineMarker(for: item)
            iconView(for: item)

            Text(itemTitle(item))
                .font(.system(size: 12.5, weight: isSelected ? .medium : .regular))
                .foregroundColor(titleColor(for: item))
                .lineLimit(1)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

            if showsRecordingDot(item) {
                Circle()
                    .fill(paletteColors.destructive.swiftUIColor)
                    .frame(width: 5, height: 5)
                    .shadow(color: paletteColors.destructive.swiftUIColor.opacity(0.7), radius: 4)
            }

            if item.dotState == .current {
                Text("current")
                    .font(.system(size: 9.5, weight: .bold))
                    .tracking(0.7)
                    .foregroundColor(paletteColors.accent.swiftUIColor.opacity(0.86))
                    .textCase(.uppercase)
            }

            switch item.kind {
            case .note, .event, .activeRecording:
                Text(timeString(for: item))
                    .font(.system(size: 11))
                    .foregroundColor(paletteColors.tertiaryText.swiftUIColor)
                    .monospacedDigit()
                    .frame(minWidth: 38, alignment: .trailing)
            case .command:
                EmptyView()
            }

            switch item.kind {
            case .event:
                createHint
            case .command:
                kbdBadge(commandShortcut(item))
            case .note:
                ZStack {
                    if showDelete, let id = noteID(for: item) {
                        deleteButton(noteID: id)
                    }
                }
                .frame(width: 26, height: 26)
            case .activeRecording:
                EmptyView()
            }
        }
        .padding(.leading, 2)
        .padding(.trailing, 10)
        .frame(minHeight: 44)
        .background(cardBackground(isSelected: isSelected, isHovering: isHovering, item: item))
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay {
            if isGhostRow(item) {
                RoundedRectangle(cornerRadius: 9)
                    .stroke(
                        paletteColors.accent.swiftUIColor.opacity(isSelected ? 0.52 : 0.34),
                        style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                    )
            } else {
                RoundedRectangle(cornerRadius: 9)
                    .stroke(cardBorderColor(isSelected: isSelected, item: item), lineWidth: 1)
            }
        }
        .animation(.easeOut(duration: 0.14), value: isSelected)
        .animation(.easeOut(duration: 0.14), value: isHovering)
    }

    private func timelineMarker(for item: SwitcherItem) -> some View {
        ZStack {
            if !isCommandRow(item) {
                Rectangle()
                    .fill(paletteColors.hairline.swiftUIColor)
                    .frame(width: 1, height: 48)
            }

            nodeDot(for: item)
        }
        .frame(width: 20, height: 44)
    }

    @ViewBuilder
    private func nodeDot(for item: SwitcherItem) -> some View {
        if isCommandRow(item) {
            Color.clear.frame(width: 7, height: 7)
        } else {
            switch item.dotState {
            case .upcoming:
                Circle()
                    .stroke(paletteColors.accent.swiftUIColor, lineWidth: 1.5)
                    .frame(width: 7, height: 7)
            case .current:
                Circle()
                    .fill(paletteColors.accent.swiftUIColor)
                    .frame(width: 6, height: 6)
                    .shadow(color: paletteColors.accent.swiftUIColor.opacity(0.6), radius: 5)
            case .past:
                Circle()
                    .fill(paletteColors.secondaryText.swiftUIColor)
                    .frame(width: 4, height: 4)
                    .opacity(0.3)
            }
        }
    }

    private func iconView(for item: SwitcherItem) -> some View {
        Image(systemName: sfIconName(for: item))
            .font(.system(size: 14, weight: .regular))
            .foregroundColor(iconForeground(for: item))
            .frame(width: 16, height: 16)
    }

    private var createHint: some View {
        HStack(spacing: 4) {
            Image(systemName: "plus")
                .font(.system(size: 9.5, weight: .semibold))
            Text("Create note")
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundColor(paletteColors.accent.swiftUIColor.opacity(0.86))
    }

    private func deleteButton(noteID id: String) -> some View {
        Button {
            bridge.deleteNote(id)
        } label: {
            Image(systemName: "trash")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(paletteColors.secondaryText.swiftUIColor)
                .frame(width: 26, height: 26)
                .background(paletteColors.fieldFill.swiftUIColor)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7)
                    .stroke(paletteColors.fieldBorder.swiftUIColor, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help("Delete note")
        .accessibilityLabel("Delete note")
        .accessibilityIdentifier("switcherDeleteButton_\(id)")
    }

    // MARK: - Styling

    private func cardBackground(isSelected: Bool, isHovering: Bool, item: SwitcherItem) -> Color {
        if isSelected {
            return paletteColors.accent.swiftUIColor.opacity(0.16)
        }
        if isGhostRow(item) {
            return paletteColors.accent.swiftUIColor.opacity(0.055)
        }
        if isHovering {
            return paletteColors.hoverFill.swiftUIColor
        }
        if case .activeRecording = item.kind {
            return paletteColors.accent.swiftUIColor.opacity(0.07)
        }
        return .clear
    }

    private func cardBorderColor(isSelected: Bool, item: SwitcherItem) -> Color {
        if isSelected {
            return paletteColors.accent.swiftUIColor.opacity(0.45)
        }
        if case .activeRecording = item.kind {
            return paletteColors.accent.swiftUIColor.opacity(0.22)
        }
        return .clear
    }

    private func iconForeground(for item: SwitcherItem) -> Color {
        if case .activeRecording = item.kind {
            return paletteColors.accent.swiftUIColor
        }
        if isGhostRow(item) {
            return paletteColors.accent.swiftUIColor.opacity(0.72)
        }
        if item.dotState == .current {
            return paletteColors.primaryText.swiftUIColor
        }
        return paletteColors.secondaryText.swiftUIColor
    }

    private func titleColor(for item: SwitcherItem) -> Color {
        if isGhostRow(item) {
            return paletteColors.secondaryText.swiftUIColor
        }
        return paletteColors.primaryText.swiftUIColor
    }

    private func isGhostRow(_ item: SwitcherItem) -> Bool {
        if case .event = item.kind { return true }
        return false
    }

    private func isCommandRow(_ item: SwitcherItem) -> Bool {
        if case .command = item.kind { return true }
        return false
    }

    private func showsRecordingDot(_ item: SwitcherItem) -> Bool {
        if case .activeRecording = item.kind { return true }
        return item.isRecording
    }

    // MARK: - Footer hints

    private var hintsFooter: some View {
        HStack(spacing: 8) {
            hint(key: "↩", text: "Open")
            Text("·")
                .font(.system(size: 11))
                .foregroundColor(paletteColors.tertiaryText.swiftUIColor.opacity(0.65))
            hint(key: "⌘N", text: "New")
            Text("·")
                .font(.system(size: 11))
                .foregroundColor(paletteColors.tertiaryText.swiftUIColor.opacity(0.65))
            hint(key: "esc", text: "")
        }
        .frame(maxWidth: .infinity)
        .frame(height: 34)
        .overlay(
            Rectangle()
                .fill(paletteColors.hairline.swiftUIColor)
                .frame(height: 1),
            alignment: .top
        )
    }

    private func hint(key: String, text: String) -> some View {
        HStack(spacing: 5) {
            kbdBadge(key)
            if !text.isEmpty {
                Text(text)
                    .font(.system(size: 11))
                    .foregroundColor(paletteColors.tertiaryText.swiftUIColor)
            }
        }
    }

    private func kbdBadge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(paletteColors.secondaryText.swiftUIColor)
            .padding(.horizontal, 5)
            .frame(minWidth: 20, minHeight: 18)
            .background(paletteColors.kbdBackground.swiftUIColor)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4)
                .stroke(paletteColors.kbdBorder.swiftUIColor, lineWidth: 1))
    }

    // MARK: - Keyboard shortcuts

    private var keyboardButtons: some View {
        Group {
            Button("") { bridge.dismiss() }
                .keyboardShortcut(.escape, modifiers: [])
                .hidden()
            Button("") { bridge.openOrCreateSelected() }
                .keyboardShortcut(.return, modifiers: [])
                .hidden()
            Button("") { bridge.triggerCreateBlankNote() }
                .keyboardShortcut("n", modifiers: .command)
                .hidden()
            Button("") { deleteSelectedNoteIfNote() }
                .keyboardShortcut(.delete, modifiers: .command)
                .hidden()
        }
    }

    // MARK: - Helpers

    private func sfIconName(for item: SwitcherItem) -> String {
        switch SwitcherViewModel.iconKind(for: item) {
        case .videoCall:    return "video"
        case .groupMeeting: return "person.2"
        case .oneOnOne:     return "person"
        case .soloNote:     return "doc.text"
        case .ghostEvent:   return "calendar"
        case .recording:    return "record.circle"
        case .openSettings: return "gearshape"
        case .newNote:      return "plus.square"
        }
    }

    private func noteID(for item: SwitcherItem) -> String? {
        if case .note(let id, _, _, _) = item.kind { return id }
        return nil
    }

    private func deleteSelectedNoteIfNote() {
        guard let item = bridge.viewModel.selectedItem, let id = noteID(for: item) else { return }
        bridge.deleteNote(id)
    }

    private func focusSearchField() {
        searchFocused = true
        DispatchQueue.main.async {
            searchFocused = true
        }
    }

    private func itemTitle(_ item: SwitcherItem) -> String {
        switch item.kind {
        case .note(_, let title, _, _):       return title
        case .event(let ev):                  return ev.title
        case .activeRecording(let recording): return recording.title
        case .command(let cmd):               return cmd.title
        }
    }

    private func commandShortcut(_ item: SwitcherItem) -> String {
        if case .command(let cmd) = item.kind { return cmd.shortcut }
        return ""
    }

    private func timeString(for item: SwitcherItem) -> String {
        switch item.kind {
        case .note(_, _, let d, _):        return HHmm(d)
        case .event(let ev):               return HHmm(ev.start)
        case .activeRecording(let rec):    return HHmm(rec.startedAt)
        case .command:                     return ""
        }
    }

    private static let hhmmFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private func HHmm(_ date: Date) -> String {
        Self.hhmmFormatter.string(from: date)
    }

    private func rowID(flatIndex: Int, item: SwitcherItem) -> String {
        "row-\(flatIndex)-\(item.switcherOverlayID)"
    }

    private func flatIndex(group: SwitcherGroup, itemOffset: Int) -> Int {
        var idx = 0
        let targetID = group.switcherOverlayID
        for g in bridge.groups {
            if g.switcherOverlayID == targetID { return idx + itemOffset }
            idx += g.items.count
        }
        return idx + itemOffset
    }

    private func tap(item: SwitcherItem) {
        switch item.kind {
        case .note(let id, _, _, _):
            bridge.onOpenNote?(id)
            bridge.dismiss()
        case .activeRecording(let recording):
            bridge.onOpenNote?(recording.noteID)
            bridge.dismiss()
        case .event(let ev):
            bridge.openOrCreate(event: ev)
        case .command(let cmd):
            switch cmd.id {
            case .openSettings:
                bridge.dismiss()
                bridge.onOpenSettings?()
            case .newNote:
                bridge.triggerCreateBlankNote()
            }
        }
    }
}

enum SwitcherOverlayPalette {
    static func colors(for appearance: Appearance, colorScheme: ColorScheme) -> ThemeColors {
        switch appearance {
        case .dark:
            return Theme.dark
        case .light:
            return Theme.light
        case .glass:
            return colorScheme == .light ? Theme.light : Theme.dark
        }
    }
}

private extension SwitcherItem {
    var switcherOverlayID: String {
        switch kind {
        case .note(let id, _, _, _):
            return "note-\(id)"
        case .event(let event):
            return "event-\(event.id)"
        case .activeRecording(let recording):
            return "recording-\(recording.noteID)"
        case .command(let command):
            return "command-\(command.id.rawValue)"
        }
    }
}

private extension SwitcherGroup {
    var switcherOverlayID: String {
        ([label] + items.map(\.switcherOverlayID)).joined(separator: "|")
    }
}

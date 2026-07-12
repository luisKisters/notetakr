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

            TextField("Search...", text: $bridge.searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundColor(paletteColors.primaryText.swiftUIColor)
                .focused($searchFocused)
                .onKeyPress(.upArrow) { bridge.moveUp(); return .handled }
                .onKeyPress(.downArrow) { bridge.moveDown(); return .handled }
                .accessibilityIdentifier("switcherSearchField")

            kbdBadge("esc")
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
        HStack(spacing: 12) {
            iconView(for: item)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(itemTitle(item))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(paletteColors.primaryText.swiftUIColor)
                        .lineLimit(1)

                    statusPill(for: item)
                }

                Text(itemSubtitle(item))
                    .font(.system(size: 11.5))
                    .foregroundColor(paletteColors.secondaryText.swiftUIColor)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

            rowActions(item: item, showDelete: showDelete)
        }
        .padding(.leading, 11)
        .padding(.trailing, 10)
        .frame(minHeight: 54)
        .background(cardBackground(isSelected: isSelected, isHovering: isHovering, item: item))
        .clipShape(RoundedRectangle(cornerRadius: 11))
        .overlay(
            RoundedRectangle(cornerRadius: 11)
                .stroke(cardBorderColor(isSelected: isSelected, item: item), lineWidth: 1)
        )
        .animation(.easeOut(duration: 0.14), value: isSelected)
        .animation(.easeOut(duration: 0.14), value: isHovering)
    }

    private func iconView(for item: SwitcherItem) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(iconBackground(for: item))
                .frame(width: 28, height: 28)
            Image(systemName: sfIconName(for: item))
                .font(.system(size: 12.5, weight: .regular))
                .foregroundColor(iconForeground(for: item))
        }
        .frame(width: 28, height: 28)
    }

    @ViewBuilder
    private func statusPill(for item: SwitcherItem) -> some View {
        switch item.kind {
        case .activeRecording:
            Text("REC")
                .font(.system(size: 9.5, weight: .bold))
                .tracking(0.5)
                .foregroundColor(paletteColors.destructive.swiftUIColor)
                .padding(.horizontal, 6)
                .frame(height: 18)
                .background(paletteColors.destructive.swiftUIColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5)
                    .stroke(paletteColors.destructive.swiftUIColor.opacity(0.42), lineWidth: 1))
        case .event where item.dotState == .current:
            Text("NOW")
                .font(.system(size: 9.5, weight: .bold))
                .tracking(0.5)
                .foregroundColor(paletteColors.accent.swiftUIColor)
                .padding(.horizontal, 6)
                .frame(height: 18)
                .background(paletteColors.accent.swiftUIColor.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5)
                    .stroke(paletteColors.accent.swiftUIColor.opacity(0.38), lineWidth: 1))
        default:
            EmptyView()
        }
    }

    private func rowActions(item: SwitcherItem, showDelete: Bool) -> some View {
        HStack(spacing: 6) {
            if let id = noteID(for: item) {
                ZStack {
                    if showDelete {
                        deleteButton(noteID: id)
                    }
                }
                .frame(width: 26, height: 26)
            }

            switch item.kind {
            case .event(_):
                actionBadge(icon: "plus", text: "Create", accent: true)
            case .note(_, _, _, _), .activeRecording(_):
                actionBadge(icon: "arrow.up.right", text: "Open", accent: false)
            case .command(_):
                kbdBadge(commandShortcut(item))
            }
        }
    }

    private func actionBadge(icon: String, text: String, accent: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            Text(text)
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundColor(accent ? paletteColors.accent.swiftUIColor : paletteColors.primaryText.swiftUIColor)
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(actionBackground(accent: accent))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7)
            .stroke(actionBorder(accent: accent), lineWidth: 1))
        .accessibilityIdentifier("switcher\(text)Action")
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
        return paletteColors.secondaryText.swiftUIColor
    }

    private func iconBackground(for item: SwitcherItem) -> Color {
        if case .activeRecording = item.kind {
            return paletteColors.accent.swiftUIColor.opacity(0.16)
        }
        return paletteColors.elevatedFill.swiftUIColor
    }

    private func actionBackground(accent: Bool) -> Color {
        accent ? paletteColors.accent.swiftUIColor.opacity(0.14)
               : paletteColors.fieldFill.swiftUIColor
    }

    private func actionBorder(accent: Bool) -> Color {
        accent ? paletteColors.accent.swiftUIColor.opacity(0.42)
               : paletteColors.fieldBorder.swiftUIColor
    }

    // MARK: - Footer hints

    private var hintsFooter: some View {
        HStack(spacing: 14) {
            hint(key: "↩", text: "Open")
            hint(key: "↑", text: "")
            hint(key: "↓", text: "Move")
            hint(key: "⌘⌫", text: "Delete")
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

    private func itemSubtitle(_ item: SwitcherItem) -> String {
        switch item.kind {
        case .note(_, _, _, _), .event(_), .activeRecording(_):
            return timeString(for: item)
        case .command:
            return commandSubtitle(item)
        }
    }

    private func commandSubtitle(_ item: SwitcherItem) -> String {
        if case .command(let cmd) = item.kind { return cmd.subtitle }
        return ""
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

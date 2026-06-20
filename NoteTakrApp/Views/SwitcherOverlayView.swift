import SwiftUI
import NoteTakrKit

// MARK: - SwitcherOverlayView

/// Full-size palette overlay shown over the editor when ⌘K is pressed.
/// Rows float as cards over a pure backdrop blur — no scrim, no dark tint.
struct SwitcherOverlayView: View {
    @ObservedObject var bridge: SwitcherBridge
    @Environment(\.themeColors) private var themeColors
    @FocusState private var searchFocused: Bool
    @State private var hoveredIndex: Int? = nil

    var body: some View {
        ZStack {
            // Pure blur — NO scrim, NO dark overlay.
            // .ultraThinMaterial adapts to system appearance and provides
            // the blur without adding a heavy tint on top of the note content.
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                searchBar
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)

                rowList

                hintsFooter
            }
            // Small top inset — just enough to clear the native traffic-light/close button.
            .padding(.top, 14)
        }
        .onAppear { focusSearchField() }
        .background(keyboardButtons)
    }

    // MARK: - Search bar (rounded, NO magnifying-glass icon)

    private var searchBar: some View {
        TextField("Search meetings\u{2026}", text: $bridge.searchQuery)
            .textFieldStyle(.plain)
            .font(.system(size: 15))
            .foregroundColor(themeColors.primaryText.swiftUIColor)
            .focused($searchFocused)
            .onKeyPress(.upArrow)   { bridge.moveUp();   return .handled }
            .onKeyPress(.downArrow) { bridge.moveDown(); return .handled }
            .padding(.horizontal, 15)
            .padding(.vertical, 11)
            .background(themeColors.fieldFill.swiftUIColor)
            .overlay(
                RoundedRectangle(cornerRadius: 13)
                    .stroke(themeColors.fieldBorder.swiftUIColor, lineWidth: 1)
            )
            .cornerRadius(13)
    }

    // MARK: - Row list with fade mask

    private var rowList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(bridge.groups, id: \.switcherOverlayID) { group in
                        rowGroupSection(group: group)
                    }
                    if bridge.groups.isEmpty {
                        Text("No meetings match your search.")
                            .font(.system(size: 12.5))
                            .foregroundColor(themeColors.tertiaryText.swiftUIColor)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 28)
                            .padding(.horizontal, 20)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 14)
            }
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.04),
                        .init(color: .black, location: 0.96),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .onChange(of: bridge.selectedIndex) { _, idx in
                guard let item = bridge.viewModel.selectedItem else { return }
                withAnimation(.easeOut(duration: 0.1)) {
                    proxy.scrollTo(rowID(flatIndex: idx, item: item), anchor: .center)
                }
            }
        }
    }

    @ViewBuilder
    private func rowGroupSection(group: SwitcherGroup) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(group.label.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(themeColors.tertiaryText.swiftUIColor)
                .tracking(1.0)
                .padding(.horizontal, 8)
                .padding(.top, 12)
                .padding(.bottom, 6)
                .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(Array(group.items.enumerated()), id: \.element.switcherOverlayID) { offset, item in
                let flatIdx = flatIndex(group: group, itemOffset: offset)
                twoLineRow(item: item, flatIndex: flatIdx)
                    .id(rowID(flatIndex: flatIdx, item: item))
            }
        }
        .id(group.switcherOverlayID)
    }

    @ViewBuilder
    private func twoLineRow(item: SwitcherItem, flatIndex: Int) -> some View {
        let isSelected = bridge.selectedIndex == flatIndex
        // Hover must NOT be purple when the row is selected — never stack purple on purple.
        let isHovering = !isSelected && hoveredIndex == flatIndex
        let isGhost = isGhostItem(item)
        let isCommand = isCommandItem(item)
        let showDelete = (hoveredIndex == flatIndex || isSelected) && noteID(for: item) != nil

        Button {
            tap(item: item)
        } label: {
            rowCard(item: item, isSelected: isSelected, isHovering: isHovering,
                    isGhost: isGhost, isCommand: isCommand)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .trailing) {
            // Trash control floats over the row's trailing edge so its hit target
            // is independent of the row's open button. Notes only.
            if showDelete, let id = noteID(for: item) {
                deleteButton(noteID: id)
                    .padding(.trailing, 10)
            }
        }
        .padding(.bottom, 7)
        .onHover { isHov in
            hoveredIndex = isHov ? flatIndex : (hoveredIndex == flatIndex ? nil : hoveredIndex)
        }
    }

    /// Small trash affordance shown on note rows (hover/selected). Deliberately compact
    /// so it isn't fired by accident.
    private func deleteButton(noteID id: String) -> some View {
        Button {
            bridge.deleteNote(id)
        } label: {
            Image(systemName: "trash")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(themeColors.secondaryText.swiftUIColor)
                .frame(width: 22, height: 22)
                .background(themeColors.kbdBackground.swiftUIColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(themeColors.kbdBorder.swiftUIColor, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help("Delete note")
    }

    @ViewBuilder
    private func rowCard(item: SwitcherItem, isSelected: Bool, isHovering: Bool,
                         isGhost: Bool, isCommand: Bool) -> some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(themeColors.primaryText.swiftUIColor.opacity(0.08))
                    .frame(width: 30, height: 30)
                Image(systemName: sfIconName(for: item))
                    .font(.system(size: 14, weight: .light))
                    .foregroundColor(themeColors.secondaryText.swiftUIColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(itemTitle(item))
                    .font(.system(size: 13))
                    .foregroundColor(themeColors.primaryText.swiftUIColor)
                    .lineLimit(1)
                Text(isCommand ? commandSubtitle(item) : itemSubtitle(item))
                    .font(.system(size: 11))
                    .foregroundColor(themeColors.tertiaryText.swiftUIColor)
                    .lineLimit(1)
            }

            Spacer()

            rowAccessory(item: item, isGhost: isGhost, isCommand: isCommand)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground(isSelected: isSelected, isHovering: isHovering))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(cardBorderColor(isSelected: isSelected, isGhost: isGhost), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(isSelected ? 0.22 : 0.16),
                radius: isSelected ? 7 : 4.5, x: 0, y: 2)
    }

    private func cardBackground(isSelected: Bool, isHovering: Bool) -> Color {
        if isSelected  { return themeColors.accent.swiftUIColor.opacity(0.16) }
        if isHovering  { return themeColors.hoverFill.swiftUIColor }
        return themeColors.fieldFill.swiftUIColor
    }

    private func cardBorderColor(isSelected: Bool, isGhost: Bool) -> Color {
        if isSelected { return themeColors.accent.swiftUIColor.opacity(0.34) }
        if isGhost    { return themeColors.accent.swiftUIColor.opacity(0.38) }
        return themeColors.hairline.swiftUIColor
    }

    @ViewBuilder
    private func rowAccessory(item: SwitcherItem, isGhost: Bool, isCommand: Bool) -> some View {
        if isGhost && canCreateGhostEvent(item) {
            HStack(spacing: 3) {
                Image(systemName: "plus").font(.system(size: 9, weight: .semibold))
                Text("Create")
            }
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundColor(themeColors.accent.swiftUIColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(themeColors.accent.swiftUIColor.opacity(0.14))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .stroke(themeColors.accent.swiftUIColor.opacity(0.34), lineWidth: 1))
            .cornerRadius(6)
        } else if isGhost {
            Text(timeString(for: item))
                .font(.system(size: 11))
                .foregroundColor(themeColors.tertiaryText.swiftUIColor)
                .monospacedDigit()
        } else if isCommand {
            kbdBadge(commandShortcut(item))
        } else {
            HStack(spacing: 6) {
                if item.dotState == .current {
                    Text("now")
                        .font(.system(size: 8.5, weight: .bold))
                        .tracking(0.06)
                        .textCase(.uppercase)
                        .foregroundColor(themeColors.accent.swiftUIColor)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(themeColors.accent.swiftUIColor.opacity(0.15))
                        .overlay(RoundedRectangle(cornerRadius: 5)
                            .stroke(themeColors.accent.swiftUIColor.opacity(0.32), lineWidth: 1))
                        .cornerRadius(5)
                }
                Text(timeString(for: item))
                    .font(.system(size: 11))
                    .foregroundColor(themeColors.tertiaryText.swiftUIColor)
                    .monospacedDigit()
            }
        }
    }

    // MARK: - Footer hints

    private var hintsFooter: some View {
        HStack(spacing: 6) {
            kbdBadge("↩")
            Text("Open")
                .font(.system(size: 10.5))
                .foregroundColor(themeColors.tertiaryText.swiftUIColor)
            Text("·")
                .font(.system(size: 10.5))
                .foregroundColor(themeColors.tertiaryText.swiftUIColor.opacity(0.5))
                .padding(.horizontal, 1)
            kbdBadge("⌘N")
            Text("New")
                .font(.system(size: 10.5))
                .foregroundColor(themeColors.tertiaryText.swiftUIColor)
            Text("·")
                .font(.system(size: 10.5))
                .foregroundColor(themeColors.tertiaryText.swiftUIColor.opacity(0.5))
                .padding(.horizontal, 1)
            kbdBadge("esc")
            Text("Close")
                .font(.system(size: 10.5))
                .foregroundColor(themeColors.tertiaryText.swiftUIColor)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 30)
        .overlay(
            Rectangle()
                .fill(themeColors.hairline.swiftUIColor)
                .frame(height: 1),
            alignment: .top
        )
    }

    // MARK: - Keyboard shortcuts (hidden, always active while overlay is shown)

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
            // ⌘⌫ deletes the selected note (notes only; no-op on events/commands).
            // Uses Command so it never collides with backspace in the search field.
            Button("") { deleteSelectedNoteIfNote() }
                .keyboardShortcut(.delete, modifiers: .command)
                .hidden()
        }
    }

    // MARK: - Helpers

    private func kbdBadge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(themeColors.secondaryText.swiftUIColor)
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(themeColors.kbdBackground.swiftUIColor)
            .overlay(RoundedRectangle(cornerRadius: 4)
                .stroke(themeColors.kbdBorder.swiftUIColor, lineWidth: 1))
            .cornerRadius(4)
    }

    private func sfIconName(for item: SwitcherItem) -> String {
        switch SwitcherViewModel.iconKind(for: item) {
        case .videoCall:    return "video"
        case .groupMeeting: return "person.2"
        case .oneOnOne:     return "person"
        case .soloNote:     return "doc.text"
        case .ghostEvent:   return "calendar"
        case .openSettings: return "gearshape"
        case .newNote:      return "plus.square"
        }
    }

    /// Note id for a row, or nil for events/commands (which are not deletable).
    private func noteID(for item: SwitcherItem) -> String? {
        if case .note(let id, _, _, _) = item.kind { return id }
        return nil
    }

    /// Deletes the currently selected row if (and only if) it is a note.
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
        case .note(_, let title, _, _): return title
        case .event(let ev):            return ev.title
        case .command(let cmd):         return cmd.title
        }
    }

    private func itemSubtitle(_ item: SwitcherItem) -> String {
        switch item.kind {
        case .note(_, _, _, let participants):
            let count = participants.count
            if count == 1 { return "2 people" }
            if count > 1  { return "\(count + 1) people" }
            return ""
        case .event(let ev):
            var parts: [String] = []
            let count = ev.participants.count
            if count == 1      { parts.append("1 person") }
            else if count > 1  { parts.append("\(count) people") }
            if let link = ev.meetingLink {
                if link.contains("zoom")        { parts.append("Zoom") }
                else if link.contains("meet.google") { parts.append("Meet") }
                else if link.contains("teams")  { parts.append("Teams") }
            }
            if let loc = ev.locationText, !loc.isEmpty { parts.append(loc) }
            return parts.joined(separator: " \u{B7} ")
        case .command: return ""
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
        case .note(_, _, let d, _): return HHmm(d)
        case .event(let ev):        return HHmm(ev.start)
        case .command:              return ""
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

    private func isGhostItem(_ item: SwitcherItem) -> Bool {
        if case .event = item.kind { return true }
        return false
    }

    private func isCommandItem(_ item: SwitcherItem) -> Bool {
        if case .command = item.kind { return true }
        return false
    }

    private func canCreateGhostEvent(_ item: SwitcherItem) -> Bool {
        guard isGhostItem(item) else { return false }
        return item.dotState != .upcoming
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
        case .event(let ev):
            guard canCreateGhostEvent(item) else { return }
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

private extension SwitcherItem {
    var switcherOverlayID: String {
        switch kind {
        case .note(let id, _, _, _):
            return "note-\(id)"
        case .event(let event):
            return "event-\(event.id)"
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

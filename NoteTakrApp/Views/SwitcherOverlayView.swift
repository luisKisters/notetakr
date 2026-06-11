import SwiftUI
import NoteTakrKit

private let accentColor  = Color(red: 0.545, green: 0.361, blue: 0.965)   // #8B5CF6
private let accentLight  = Color(red: 0.655, green: 0.545, blue: 0.980)   // #A78BFA

// MARK: - Display mode

enum SwitcherDisplayMode: String, CaseIterable {
    case rows
    case timeline
}

// MARK: - SwitcherOverlayView

/// Full-size frost overlay shown over the editor when ⌘K is pressed.
/// Primary mode: two-line rows (title + subtitle). Secondary: timeline rail with dots.
struct SwitcherOverlayView: View {
    @ObservedObject var bridge: SwitcherBridge
    @FocusState private var searchFocused: Bool

    @State private var displayMode: SwitcherDisplayMode = .rows

    private let gutterLeft: CGFloat = 14

    var body: some View {
        ZStack {
            // Frost backdrop
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.black.opacity(0.22))

            VStack(spacing: 0) {
                searchBar
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .padding(.bottom, 6)

                if displayMode == .timeline {
                    timelineList
                } else {
                    rowList
                }

                hintsFooter
            }
        }
        .onAppear { searchFocused = true }
        .background(keyboardButtons)
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .light))
                .foregroundColor(Color.white.opacity(0.40))

            TextField("Search meetings\u{2026}", text: $bridge.searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundColor(.white)
                .focused($searchFocused)
                .onKeyPress(.upArrow)    { bridge.moveUp();                  return .handled }
                .onKeyPress(.downArrow)  { bridge.moveDown();                return .handled }
                .onKeyPress(.return)     { bridge.openOrCreateSelected();    return .handled }
                .onKeyPress(.escape)     { bridge.dismiss();                 return .handled }

            // Toggle rows ↔ timeline
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    displayMode = displayMode == .rows ? .timeline : .rows
                }
            } label: {
                Image(systemName: displayMode == .rows ? "calendar" : "list.bullet")
                    .font(.system(size: 11, weight: .light))
                    .foregroundColor(Color.white.opacity(0.40))
            }
            .buttonStyle(.plain)
            .help("Toggle between rows and timeline view")

            kbdBadge("⌘K")
        }
        .padding(.horizontal, 11)
        .frame(height: 36)
        .background(Color.white.opacity(0.07))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.13), lineWidth: 1))
        .cornerRadius(10)
    }

    // MARK: - Two-line row list (primary)

    private var rowList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(bridge.groups, id: \.label) { group in
                        rowGroupSection(group: group)
                    }
                    if bridge.groups.isEmpty {
                        Text("No meetings match your search.")
                            .font(.system(size: 12))
                            .foregroundColor(Color.white.opacity(0.38))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 10)
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
            .onChange(of: bridge.selectedIndex) { idx in
                withAnimation(.easeOut(duration: 0.1)) {
                    proxy.scrollTo("row-\(idx)", anchor: .center)
                }
            }
        }
    }

    @ViewBuilder
    private func rowGroupSection(group: SwitcherGroup) -> some View {
        Text(group.label.uppercased())
            .font(.system(size: 9.5, weight: .bold))
            .foregroundColor(Color.white.opacity(0.38))
            .tracking(1.3)
            .padding(.horizontal, 10)
            .padding(.top, 11)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity, alignment: .leading)

        ForEach(Array(group.items.enumerated()), id: \.offset) { offset, item in
            let flatIdx = flatIndex(group: group, itemOffset: offset)
            twoLineRow(item: item, flatIndex: flatIdx)
                .id("row-\(flatIdx)")
        }
    }

    @ViewBuilder
    private func twoLineRow(item: SwitcherItem, flatIndex: Int) -> some View {
        let isSelected = bridge.selectedIndex == flatIndex
        let isGhost = isGhostItem(item)
        let isCommand = isCommandItem(item)

        Button {
            tap(item: item)
        } label: {
            HStack(spacing: 10) {
                // Icon bubble
                ZStack {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.white.opacity(isSelected ? 0.12 : 0.06))
                        .frame(width: 26, height: 26)
                    Image(systemName: sfIconName(for: item))
                        .font(.system(size: 13, weight: .light))
                        .foregroundColor(Color.white.opacity(isSelected ? 0.9 : 0.50))
                }

                // Title + subtitle
                VStack(alignment: .leading, spacing: 1) {
                    Text(itemTitle(item))
                        .font(.system(size: 12.5, weight: isSelected ? .medium : .regular))
                        .foregroundColor(isGhost ? Color.white.opacity(0.65) : Color.white.opacity(isSelected ? 1 : 0.88))
                        .lineLimit(1)

                    if !isCommand {
                        Text(itemSubtitle(item))
                            .font(.system(size: 10.5))
                            .foregroundColor(Color.white.opacity(0.38))
                            .lineLimit(1)
                    } else {
                        Text(commandSubtitle(item))
                            .font(.system(size: 10.5))
                            .foregroundColor(Color.white.opacity(0.38))
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Right accessories
                if isGhost {
                    HStack(spacing: 3) {
                        Image(systemName: "plus")
                            .font(.system(size: 9, weight: .semibold))
                        Text("Create")
                    }
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundColor(accentLight)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(accentColor.opacity(0.14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(accentColor.opacity(0.34), lineWidth: 1)
                    )
                    .cornerRadius(6)
                } else if isCommand {
                    kbdBadge(commandShortcut(item))
                } else {
                    HStack(spacing: 6) {
                        if item.dotState == .current {
                            Text("now")
                                .font(.system(size: 8.5, weight: .bold))
                                .tracking(0.06)
                                .textCase(.uppercase)
                                .foregroundColor(accentLight)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(accentColor.opacity(0.14))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5)
                                        .stroke(accentColor.opacity(0.30), lineWidth: 1)
                                )
                                .cornerRadius(5)
                        }
                        Text(timeString(for: item))
                            .font(.system(size: 10.5))
                            .foregroundColor(Color.white.opacity(0.38))
                            .monospacedDigit()
                    }
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground(isSelected: isSelected, isGhost: isGhost))
            .cornerRadius(9)
            .overlay(
                isGhost
                    ? RoundedRectangle(cornerRadius: 9)
                        .stroke(accentColor.opacity(0.38), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    : nil
            )
            .overlay(
                !isGhost
                    ? RoundedRectangle(cornerRadius: 9)
                        .stroke(
                            isSelected
                                ? accentColor.opacity(0.26)
                                : Color.white.opacity(0.0),
                            lineWidth: 1
                        )
                    : nil
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 2)
        .padding(.bottom, 1)
    }

    // MARK: - Timeline list (secondary)

    private var timelineList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                ZStack(alignment: .topLeading) {
                    timelineLine
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(bridge.groups, id: \.label) { group in
                            timelineGroupSection(group: group)
                        }
                    }
                    .padding(.leading, gutterLeft * 2 + 16)
                }
                .padding(.bottom, 10)
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
            .onChange(of: bridge.selectedIndex) { idx in
                withAnimation(.easeOut(duration: 0.1)) {
                    proxy.scrollTo("tl-row-\(idx)", anchor: .center)
                }
            }
        }
    }

    private var timelineLine: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(Color.white.opacity(0.09))
                .frame(width: 1, height: geo.size.height)
                .offset(x: gutterLeft + 7)
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: 0.05),
                            .init(color: .black, location: 0.95),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func timelineGroupSection(group: SwitcherGroup) -> some View {
        Text(group.label.uppercased())
            .font(.system(size: 9.5, weight: .bold))
            .foregroundColor(Color.white.opacity(0.38))
            .tracking(1.3)
            .padding(.horizontal, 8)
            .padding(.top, 11)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity, alignment: .leading)

        ForEach(Array(group.items.enumerated()), id: \.offset) { offset, item in
            let flatIdx = flatIndex(group: group, itemOffset: offset)
            timelineRow(item: item, flatIndex: flatIdx)
                .id("tl-row-\(flatIdx)")
        }
    }

    @ViewBuilder
    private func timelineRow(item: SwitcherItem, flatIndex: Int) -> some View {
        let isSelected = bridge.selectedIndex == flatIndex
        let isGhost = isGhostItem(item)

        Button {
            tap(item: item)
        } label: {
            HStack(spacing: 10) {
                // Node dot centered on the timeline line
                nodeDot(for: item.dotState)
                    .frame(width: gutterLeft * 2, height: 14, alignment: .center)
                    .offset(x: -(gutterLeft * 2 + 16))

                // Icon
                Image(systemName: sfIconName(for: item))
                    .font(.system(size: 13, weight: .light))
                    .foregroundColor(isSelected ? Color.white.opacity(0.9) : Color.white.opacity(0.40))
                    .frame(width: 16)
                    .offset(x: -(gutterLeft * 2 + 16))

                // Title
                Text(itemTitle(item))
                    .font(.system(size: 12.5, weight: isSelected ? .medium : .regular))
                    .foregroundColor(isGhost ? Color.white.opacity(0.65) : Color.white.opacity(isSelected ? 1 : 0.88))
                    .lineLimit(1)
                    .offset(x: -(gutterLeft * 2 + 16))

                Spacer()

                // Right accessories
                if isGhost {
                    HStack(spacing: 3) {
                        Image(systemName: "plus")
                            .font(.system(size: 9, weight: .semibold))
                        Text("Create")
                    }
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundColor(accentLight)
                } else {
                    HStack(spacing: 6) {
                        if item.dotState == .current {
                            Text("now")
                                .font(.system(size: 8.5, weight: .bold))
                                .tracking(0.06)
                                .textCase(.uppercase)
                                .foregroundColor(accentLight)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(accentColor.opacity(0.14))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5)
                                        .stroke(accentColor.opacity(0.30), lineWidth: 1)
                                )
                                .cornerRadius(5)
                        }
                        Text(timeString(for: item))
                            .font(.system(size: 10.5))
                            .foregroundColor(Color.white.opacity(0.38))
                            .monospacedDigit()
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.leading, gutterLeft)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground(isSelected: isSelected, isGhost: isGhost))
            .cornerRadius(9)
            .overlay(
                isGhost ? RoundedRectangle(cornerRadius: 9)
                    .stroke(accentLight.opacity(0.38), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                : nil
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .padding(.bottom, 3)
    }

    // MARK: - Footer hints

    private var hintsFooter: some View {
        HStack(spacing: 6) {
            kbdBadge("↩")
            Text("Open")
                .font(.system(size: 11))
                .foregroundColor(Color.white.opacity(0.38))
            Text("·")
                .font(.system(size: 11))
                .foregroundColor(Color.white.opacity(0.25))
                .padding(.horizontal, 2)
            kbdBadge("⌘N")
            Text("New")
                .font(.system(size: 11))
                .foregroundColor(Color.white.opacity(0.38))
            Text("·")
                .font(.system(size: 11))
                .foregroundColor(Color.white.opacity(0.25))
                .padding(.horizontal, 2)
            kbdBadge("esc")
        }
        .frame(maxWidth: .infinity)
        .frame(height: 34)
        .overlay(
            Rectangle()
                .fill(Color.white.opacity(0.09))
                .frame(height: 1),
            alignment: .top
        )
    }

    // MARK: - Keyboard shortcut buttons (invisible, always active while overlay is shown)

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
        }
    }

    // MARK: - Helpers

    private func kbdBadge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(Color.white.opacity(0.55))
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(Color.white.opacity(0.10))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.16), lineWidth: 1))
            .cornerRadius(4)
    }

    @ViewBuilder
    private func nodeDot(for state: DotState) -> some View {
        switch state {
        case .upcoming:
            Circle()
                .stroke(accentLight, lineWidth: 1.5)
                .frame(width: 7, height: 7)
        case .current:
            Circle()
                .fill(accentColor)
                .frame(width: 7, height: 7)
                .shadow(color: accentColor.opacity(0.5), radius: 3)
        case .past:
            Circle()
                .fill(Color.white.opacity(0.4))
                .frame(width: 4, height: 4)
                .opacity(0.5)
        }
    }

    private func rowBackground(isSelected: Bool, isGhost: Bool) -> some View {
        Group {
            if isSelected {
                accentColor.opacity(0.11)
            } else {
                Color.clear
            }
        }
    }

    /// Deterministic SF Symbol name derived from the item kind.
    private func sfIconName(for item: SwitcherItem) -> String {
        switch SwitcherViewModel.iconKind(for: item) {
        case .videoCall:     return "video"
        case .groupMeeting:  return "person.2"
        case .oneOnOne:      return "person"
        case .soloNote:      return "doc.text"
        case .ghostEvent:    return "calendar"
        case .openSettings:  return "gearshape"
        case .newNote:       return "plus.square"
        }
    }

    private func itemTitle(_ item: SwitcherItem) -> String {
        switch item.kind {
        case .note(_, let title, _, _): return title
        case .event(let ev):            return ev.title
        case .command(let cmd):         return cmd.title
        }
    }

    /// Subtitle for meeting rows (participants · platform hint).
    private func itemSubtitle(_ item: SwitcherItem) -> String {
        switch item.kind {
        case .note(_, _, let date, let participants):
            var parts: [String] = []
            let count = participants.count
            if count == 1 { parts.append("2 people") }
            else if count > 1 { parts.append("\(count + 1) people") }
            return parts.isEmpty ? timeString(for: item) : parts.joined(separator: " \u{B7} ")
        case .event(let ev):
            var parts: [String] = []
            let count = ev.participants.count
            if count == 1 { parts.append("2 people") }
            else if count > 1 { parts.append("\(count + 1) people") }
            if let link = ev.meetingLink {
                if link.contains("zoom") { parts.append("Zoom") }
                else if link.contains("meet.google") { parts.append("Meet") }
                else if link.contains("teams") { parts.append("Teams") }
            }
            if let loc = ev.locationText, !loc.isEmpty { parts.append(loc) }
            return parts.isEmpty ? "" : parts.joined(separator: " \u{B7} ")
        case .command:
            return ""
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
        let date: Date
        switch item.kind {
        case .note(_, _, let d, _): date = d
        case .event(let ev):        date = ev.start
        case .command:              return ""
        }
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return fmt.string(from: date)
    }

    private func isGhostItem(_ item: SwitcherItem) -> Bool {
        if case .event = item.kind { return true }
        return false
    }

    private func isCommandItem(_ item: SwitcherItem) -> Bool {
        if case .command = item.kind { return true }
        return false
    }

    private func flatIndex(group: SwitcherGroup, itemOffset: Int) -> Int {
        var idx = 0
        for g in bridge.groups {
            if g.label == group.label {
                return idx + itemOffset
            }
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

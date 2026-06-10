import SwiftUI
import NoteTakrKit

private let accent = Color(red: 0.545, green: 0.361, blue: 0.965)
private let accent2 = Color(red: 0.655, green: 0.545, blue: 0.980)

/// Full-size frost overlay shown over the editor when ⌘K is pressed.
/// Displays the Timeline Lite switcher: search field, day-grouped rows with
/// a 1px timeline rail and node dots, ghost event rows, and keyboard hints.
struct SwitcherOverlayView: View {
    @ObservedObject var bridge: SwitcherBridge
    @FocusState private var searchFocused: Bool

    private let gutterLeft: CGFloat = 14   // distance from list edge to line center
    private let rowLeadPad: CGFloat = 12   // leading padding inside a row

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

                timelineList

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

            kbdBadge("⌘K")
        }
        .padding(.horizontal, 11)
        .frame(height: 36)
        .background(Color.white.opacity(0.07))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.13), lineWidth: 1))
        .cornerRadius(10)
    }

    // MARK: - Timeline list

    private var timelineList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                ZStack(alignment: .topLeading) {
                    // Barely-there 1px vertical timeline line, fading at both ends
                    timelineLine

                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(bridge.groups, id: \.label) { group in
                            groupSection(group: group)
                        }
                    }
                }
                .padding(.bottom, 10)
            }
            .onChange(of: bridge.selectedIndex) { idx in
                withAnimation(.easeOut(duration: 0.1)) {
                    proxy.scrollTo("row-\(idx)", anchor: .center)
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
    private func groupSection(group: SwitcherGroup) -> some View {
        Text(group.label.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(Color.white.opacity(0.38))
            .tracking(1.4)
            .padding(.leading, 10 + gutterLeft * 2 + 16 + 10)
            .padding(.top, 12)
            .padding(.bottom, 5)
            .frame(maxWidth: .infinity, alignment: .leading)

        ForEach(Array(group.items.enumerated()), id: \.offset) { idx, item in
            let flatIdx = flatIndex(group: group, itemOffset: idx)
            rowView(item: item, flatIndex: flatIdx)
                .id("row-\(flatIdx)")
        }
    }

    @ViewBuilder
    private func rowView(item: SwitcherItem, flatIndex: Int) -> some View {
        let isSelected = bridge.selectedIndex == flatIndex
        let isGhost = isGhostItem(item)

        Button {
            tap(item: item)
        } label: {
            HStack(spacing: 10) {
                // Node dot in the gutter, centered on the timeline line
                nodeDot(for: item.dotState)
                    .frame(width: gutterLeft * 2, height: 14, alignment: .center)

                // Icon
                Image(systemName: iconName(for: item))
                    .font(.system(size: 13, weight: .light))
                    .foregroundColor(isSelected ? Color.white.opacity(0.9) : Color.white.opacity(0.40))
                    .frame(width: 16)

                // Title
                Text(itemTitle(item))
                    .font(.system(size: 12.5, weight: isSelected ? .medium : .regular))
                    .foregroundColor(isGhost ? Color.white.opacity(0.65) : Color.white.opacity(isSelected ? 1 : 0.88))
                    .lineLimit(1)

                Spacer()

                // Right side: current badge + time, or "Create note" for ghosts
                if isGhost {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 9, weight: .semibold))
                        Text("Create note")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(accent2)
                } else {
                    HStack(spacing: 6) {
                        if item.dotState == .current {
                            Text("current")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(accent2.opacity(0.85))
                        }
                        Text(timeString(for: item))
                            .font(.system(size: 11))
                            .foregroundColor(Color.white.opacity(0.38))
                            .monospacedDigit()
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.leading, rowLeadPad)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground(isSelected: isSelected, isGhost: isGhost))
            .cornerRadius(9)
            .overlay(
                isGhost ? RoundedRectangle(cornerRadius: 9)
                    .stroke(accent2.opacity(0.38), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
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
        .frame(height: 36)
        .background(
            VStack(spacing: 0) {
                Color.white.opacity(0.09).frame(height: 1)
                Color.white.opacity(0.02)
            },
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
                .stroke(accent2, lineWidth: 1.5)
                .frame(width: 7, height: 7)
        case .current:
            Circle()
                .fill(accent)
                .frame(width: 6, height: 6)
                .shadow(color: accent.opacity(0.6), radius: 3)
        case .past:
            Circle()
                .fill(Color.white.opacity(0.4))
                .frame(width: 4, height: 4)
                .opacity(0.3)
        }
    }

    private func rowBackground(isSelected: Bool, isGhost: Bool) -> some View {
        Group {
            if isSelected {
                LinearGradient(
                    colors: [accent2.opacity(0.26), accent.opacity(0.16)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            } else if isGhost {
                accent.opacity(0.06)
            } else {
                Color.clear
            }
        }
    }

    private func iconName(for item: SwitcherItem) -> String {
        switch item.kind {
        case .note(_, _, _, let participants):
            return participants.count > 1 ? "person.2" : "person"
        case .event:
            return "calendar"
        }
    }

    private func itemTitle(_ item: SwitcherItem) -> String {
        switch item.kind {
        case .note(_, let title, _, _): return title
        case .event(let ev): return ev.title
        }
    }

    private func timeString(for item: SwitcherItem) -> String {
        let date: Date
        switch item.kind {
        case .note(_, _, let d, _): date = d
        case .event(let ev): date = ev.start
        }
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return fmt.string(from: date)
    }

    private func isGhostItem(_ item: SwitcherItem) -> Bool {
        if case .event = item.kind { return true }
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
        }
    }
}

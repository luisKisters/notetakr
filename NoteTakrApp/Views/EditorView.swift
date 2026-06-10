import SwiftUI
import NoteTakrKit

private let tabsAccentColor = Color(red: 0.545, green: 0.361, blue: 0.965)

struct EditorView: View {
    @ObservedObject var bridge: NoteEditorBridge
    @ObservedObject var frontmatterBridge: FrontmatterPresenterBridge
    @ObservedObject var tabsBridge: NoteTabsBridge
    @ObservedObject var switcherBridge: SwitcherBridge
    @ObservedObject var settingsBridge: SettingsSheetViewModel

    @State private var isHoveringPanel: Bool = false

    var body: some View {
        ZStack {
            Color(red: 0.082, green: 0.078, blue: 0.090)
                .ignoresSafeArea()

            // ⌘K switcher overlay (sits over the entire editor when visible)
            if switcherBridge.isVisible {
                SwitcherOverlayView(bridge: switcherBridge)
                    .transition(.opacity.animation(.easeInOut(duration: 0.15)))
                    .zIndex(10)
            }

            // Settings sheet overlay
            if settingsBridge.isVisible {
                SettingsSheetView(viewModel: settingsBridge)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.22), value: settingsBridge.isVisible)
                    .zIndex(20)
            }

            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    TextField("Title", text: Binding(
                        get: { bridge.title },
                        set: { bridge.setTitle($0) }
                    ))
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 12)

                    // Gear icon — visible on panel hover or when settings are open
                    if isHoveringPanel || settingsBridge.isVisible {
                        Button {
                            withAnimation(.easeInOut(duration: 0.22)) {
                                settingsBridge.isVisible.toggle()
                            }
                        } label: {
                            Image(systemName: "gearshape")
                                .font(.system(size: 13, weight: .light))
                                .foregroundColor(settingsBridge.isVisible
                                    ? .white
                                    : Color.white.opacity(0.55))
                                .frame(width: 25, height: 25)
                                .background(settingsBridge.isVisible
                                    ? Color.white.opacity(0.12)
                                    : Color.clear)
                                .cornerRadius(7)
                                .overlay {
                                    if settingsBridge.isVisible {
                                        RoundedRectangle(cornerRadius: 7)
                                            .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 14)
                        .padding(.trailing, 14)
                        .accessibilityIdentifier("settingsGearButton")
                        .transition(.opacity)
                    }
                }
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isHoveringPanel = hovering
                    }
                }

                ChipsRowView(bridge: frontmatterBridge)

                PropertyPanelView(bridge: frontmatterBridge)
                    .animation(.easeInOut(duration: 0.2), value: frontmatterBridge.isExpanded)

                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 1)

                tabContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                footerTabs
            }
        }
        // ⌘K keyboard shortcut — always active while the panel is open
        .background(
            Button("") { switcherBridge.toggle() }
                .keyboardShortcut("k", modifiers: .command)
                .hidden()
        )
    }

    @ViewBuilder
    private var tabContent: some View {
        switch tabsBridge.selectedTab {
        case .privateNotes:
            TextEditor(text: Binding(
                get: { bridge.body },
                set: { bridge.setBody($0) }
            ))
            .font(.system(size: 14))
            .foregroundColor(.white.opacity(0.85))
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        case .summary:
            SummaryView(
                state: tabsBridge.summaryState,
                onGenerate: { tabsBridge.generateSummary() }
            )
        case .transcript:
            TranscriptView(state: tabsBridge.transcriptState)
        }
    }

    private var footerTabs: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)

            HStack(spacing: 34) {
                tabButton("Private Notes", tab: .privateNotes)
                tabButton("Summary", tab: .summary)
                tabButton("Transcript", tab: .transcript)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 42)
        }
    }

    private func tabButton(_ label: String, tab: NoteTab) -> some View {
        let isActive = tabsBridge.selectedTab == tab
        let weight: Font.Weight = isActive ? .medium : .regular
        let color: Color = isActive ? tabsAccentColor : Color.white.opacity(0.45)
        return Button(label) {
            tabsBridge.selectTab(tab)
        }
        .buttonStyle(.plain)
        .font(.system(size: 12, weight: weight))
        .foregroundColor(color)
        .animation(.easeInOut(duration: 0.15), value: tabsBridge.selectedTab)
    }
}

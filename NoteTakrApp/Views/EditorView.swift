import SwiftUI
import NoteTakrKit

struct EditorView: View {
    @ObservedObject var bridge: NoteEditorBridge
    @ObservedObject var frontmatterBridge: FrontmatterPresenterBridge
    @ObservedObject var tabsBridge: NoteTabsBridge
    @ObservedObject var switcherBridge: SwitcherBridge
    @ObservedObject var settingsBridge: SettingsSheetViewModel
    let recordPillMachine: RecordPillStateMachine
    let onRenameSpeaker: ((String, String, String) -> Void)?
    @State private var pillState: RecordPillState = .idle

    private var themeColors: ThemeColors {
        Theme.colors(for: settingsBridge.currentAppearance)
    }

    var body: some View {
        ZStack {
            // Appearance-aware background
            panelBackground
                .ignoresSafeArea()

            // ⌘K switcher overlay (sits over the entire editor when visible)
            if switcherBridge.isVisible {
                SwitcherOverlayView(
                    bridge: switcherBridge,
                    appearance: settingsBridge.currentAppearance
                )
                    .environment(\.themeColors, themeColors)
                    .transition(.opacity.animation(.easeInOut(duration: 0.15)))
                    .zIndex(10)
            }

            // Settings sheet overlay
            if settingsBridge.isVisible {
                SettingsSheetView(viewModel: settingsBridge)
                    .environment(\.themeColors, themeColors)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.22), value: settingsBridge.isVisible)
                    .zIndex(20)
            }

            VStack(alignment: .leading, spacing: 0) {
                // Window chrome: traffic lights left, gear right (always visible per mockup)
                WindowChromeView(
                    settingsIsVisible: settingsBridge.isVisible,
                    onGearTap: {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            settingsBridge.isVisible.toggle()
                        }
                    }
                )
                .environment(\.themeColors, themeColors)

                TextField("Title", text: Binding(
                    get: { bridge.title },
                    set: { bridge.setTitle($0) }
                ))
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(themeColors.primaryText.swiftUIColor)
                .textFieldStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)

                ChipsRowView(
                    bridge: frontmatterBridge,
                    machine: recordPillMachine,
                    pillState: visiblePillState,
                    onRecordPillIdleTap: inactiveRecordingPillAction
                )
                    .environment(\.themeColors, themeColors)
                    .onAppear {
                        pillState = recordPillMachine.state
                        recordPillMachine.onStateChanged = { newState in
                            DispatchQueue.main.async { self.pillState = newState }
                        }
                    }

                PropertyPanelView(
                    bridge: frontmatterBridge,
                    recordPillMachine: recordPillMachine,
                    pillState: visiblePillState,
                    onRecordPillIdleTap: inactiveRecordingPillAction,
                    availableEvents: frontmatterBridge.availableEvents
                )
                .environment(\.themeColors, themeColors)
                .animation(.easeInOut(duration: 0.2), value: frontmatterBridge.isExpanded)

                Rectangle()
                    .fill(themeColors.hairline.swiftUIColor)
                    .frame(height: 1)

                tabContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                footerTabs
            }
        }
        // ⌘K — toggle switcher
        .background(
            Button("") {
                withAnimation(.easeInOut(duration: 0.15)) { switcherBridge.toggle() }
            }
            .keyboardShortcut("k", modifiers: .command)
            .hidden()
        )
        // ⌘, — open/close settings
        .background(
            Button("") {
                withAnimation(.easeInOut(duration: 0.22)) {
                    settingsBridge.isVisible.toggle()
                }
            }
            .keyboardShortcut(",", modifiers: .command)
            .hidden()
        )
    }

    private var panelBackground: some View {
        ThemedSurface(appearance: settingsBridge.currentAppearance)
    }

    private var visiblePillState: RecordPillState {
        RecordPillStateMachine.displayState(
            actualState: pillState,
            currentNoteID: frontmatterBridge.noteID,
            activeRecordingNoteID: switcherBridge.activeRecordingNoteID
        )
    }

    private var inactiveRecordingPillAction: (() -> Void)? {
        guard let activeRecordingNoteID = switcherBridge.activeRecordingNoteID,
              activeRecordingNoteID != frontmatterBridge.noteID else {
            return nil
        }
        switch pillState {
        case .recording, .paused:
            return { switcherBridge.openActiveRecordingNote() }
        default:
            return nil
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch tabsBridge.selectedTab {
        case .privateNotes:
            NoteTakrMarkdownEditor(
                text: Binding(
                    get: { bridge.body },
                    set: { bridge.setBody($0) }
                ),
                documentId: bridge.viewModel.noteID ?? "notetakr-current-note",
                theme: themeColors
            )
        case .summary:
            SummaryView(
                state: tabsBridge.summaryState,
                onGenerate: { tabsBridge.generateSummary() },
                onTranscribeAndSummarize: tabsBridge.canGenerateTranscript
                    ? { tabsBridge.transcribeAndSummarize() } : nil
            )
            .environment(\.themeColors, themeColors)
        case .transcript:
            TranscriptView(
                state: tabsBridge.transcriptState,
                speakerResolutions: tabsBridge.speakerResolutions,
                onGenerate: tabsBridge.canGenerateTranscript
                    ? { tabsBridge.generateTranscript() } : nil,
                onRenameSpeaker: { oldName, newName in
                    guard !frontmatterBridge.noteID.isEmpty else { return }
                    onRenameSpeaker?(frontmatterBridge.noteID, oldName, newName)
                }
            )
            .environment(\.themeColors, themeColors)
        }
    }

    private var footerTabs: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(themeColors.hairline.swiftUIColor)
                .frame(height: 1)

            HStack(spacing: 34) {
                tabButton("Notes", tab: .privateNotes)
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
        let color: Color = isActive
            ? themeColors.accent.swiftUIColor
            : themeColors.primaryText.swiftUIColor.opacity(0.45)
        return Button(label) {
            withAnimation(.easeInOut(duration: 0.15)) { tabsBridge.selectTab(tab) }
        }
        .buttonStyle(.plain)
        .font(.system(size: 12, weight: weight))
        .foregroundStyle(color)
        .animation(.easeInOut(duration: 0.15), value: tabsBridge.selectedTab)
    }
}

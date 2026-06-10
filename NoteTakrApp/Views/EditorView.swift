import SwiftUI
import NoteTakrKit

private let tabsAccentColor = Color(red: 0.545, green: 0.361, blue: 0.965)

struct EditorView: View {
    @ObservedObject var bridge: NoteEditorBridge
    @ObservedObject var frontmatterBridge: FrontmatterPresenterBridge
    @ObservedObject var tabsBridge: NoteTabsBridge

    var body: some View {
        ZStack {
            Color(red: 0.082, green: 0.078, blue: 0.090)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
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

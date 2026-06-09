import SwiftUI
import NoteTakrCore

/// Root of the single app window: a sidebar with Sessions / Settings tabs and a
/// record control, plus a detail area that swaps between the sessions browser
/// and settings.
struct MainWindowView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            Group {
                switch model.selectedTab {
                case .sessions: SessionsView()
                case .calendar: CalendarView()
                case .settings: SettingsView()
                }
            }
            .frame(minWidth: 460)
        }
        .frame(minWidth: 860, minHeight: 540)
        .background(WindowAccessor { window in
            window?.isReleasedWhenClosed = false
            model.mainWindow = window
        })
    }

    private var sidebar: some View {
        List(selection: $model.selectedTab) {
            Label("Sessions", systemImage: "waveform")
                .tag(MainTab.sessions)
                .accessibilityIdentifier("tab_sessions")
            Label("Calendar", systemImage: "calendar")
                .tag(MainTab.calendar)
                .accessibilityIdentifier("tab_calendar")
            Label("Settings", systemImage: "gearshape")
                .tag(MainTab.settings)
                .accessibilityIdentifier("tab_settings")
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
        .safeAreaInset(edge: .bottom) {
            RecordControl()
                .padding(12)
        }
    }
}

/// The big primary record / stop button shown at the bottom of the sidebar.
struct RecordControl: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 8) {
            Button {
                Task { await model.toggleRecording() }
            } label: {
                Label(
                    model.isRecording ? "Stop Recording" : "Start Recording",
                    systemImage: model.isRecording ? "stop.circle.fill" : "record.circle"
                )
                .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .tint(model.isRecording ? .red : .accentColor)
            .accessibilityIdentifier("recordToggleButton")

            if !model.isRecording {
                Button {
                    Task { await model.quickRecording() }
                } label: {
                    Label("Quick Recording", systemImage: "bolt.fill")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.small)
                .buttonStyle(.bordered)
                .accessibilityIdentifier("quickRecordButton")
            }
        }
    }
}

/// Sessions tab: a list of recordings on the left and the selected session's
/// detail (transcript + notes) on the right.
struct SessionsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HSplitView {
            sessionList
                .frame(minWidth: 240, idealWidth: 280, maxWidth: 360)
            detail
                .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: model.selectedSessionID) { _ in
            model.autoTranscribeSelected()
        }
        .onAppear {
            model.autoTranscribeSelected()
        }
    }

    private var sessionList: some View {
        VStack(spacing: 0) {
            if model.nextMeeting != nil || model.isCalendarLoading {
                NextMeetingBanner()
                    .padding(12)
                Divider()
            }
            if model.sessions.isEmpty {
                emptyState
            } else {
                List(selection: $model.selectedSessionID) {
                    ForEach(model.sessions) { session in
                        SessionRowView(
                            session: session,
                            onStopRecording: session.status == .recording
                                ? { Task { await model.stopRecording() } }
                                : nil
                        )
                        .tag(session.id)
                        .contextMenu {
                            Button(role: .destructive) {
                                model.deleteSession(session)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "mic.slash")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("No recordings yet")
                .foregroundStyle(.secondary)
            Text("Press Start Recording to begin.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .accessibilityIdentifier("noSessionsLabel")
    }

    @ViewBuilder
    private var detail: some View {
        if let session = model.selectedSession {
            SessionDetailPane(sessionID: session.id)
                .id(session.id)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "waveform")
                    .font(.largeTitle)
                    .foregroundStyle(.tertiary)
                Text("Select a session")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Captures the hosting NSWindow so AppKit (the menu bar) can bring it forward.
struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { onResolve(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { onResolve(nsView.window) }
    }
}

struct NextMeetingBanner: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "calendar")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                if model.isCalendarLoading {
                    Text("Loading calendar…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let meeting = model.nextMeeting {
                    Text(meeting.title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Text(meeting.startDate, style: .time)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

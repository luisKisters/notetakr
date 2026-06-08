import SwiftUI
import NoteTakrCore

struct TodayView: View {
    let sessions: [MeetingSession]
    var nextMeeting: CalendarEvent? = nil
    var isLoading: Bool = false
    var errorMessage: String? = nil
    var onSelectSession: (MeetingSession) -> Void = { _ in }
    var onStopRecording: (MeetingSession) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox("Next Meeting") {
                nextMeetingContent
            }
            .accessibilityIdentifier("nextMeetingGroup")

            if sessions.isEmpty {
                emptySessionsView
            } else {
                Text("Recent Recordings")
                    .font(.headline)
                    .padding(.top, 4)
                List(sessions) { session in
                    SessionRowView(session: session, onStopRecording: {
                        onStopRecording(session)
                    })
                    .contentShape(Rectangle())
                    .onTapGesture { onSelectSession(session) }
                }
                .listStyle(.plain)
            }
        }
        .padding()
        .frame(minWidth: 300)
    }

    @ViewBuilder
    private var nextMeetingContent: some View {
        if isLoading {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading calendar…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("calendarLoadingIndicator")
        } else if let error = errorMessage {
            Label(error, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("calendarErrorLabel")
        } else if let meeting = nextMeeting {
            VStack(alignment: .leading, spacing: 4) {
                Text(meeting.title)
                    .fontWeight(.medium)
                    .accessibilityIdentifier("nextMeetingTitle")
                Text(meeting.startDate, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("nextMeetingTime")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text("No upcoming meetings detected")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("nextMeetingPlaceholder")
        }
    }

    private var emptySessionsView: some View {
        VStack(spacing: 8) {
            Image(systemName: "mic.slash")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
                .accessibilityIdentifier("noSessionsIcon")
            Text("No recordings yet")
                .foregroundStyle(.secondary)
            Text("Use Start Recording or Quick Recording to begin.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding()
        .accessibilityIdentifier("noSessionsLabel")
    }
}

struct SessionRowView: View {
    let session: MeetingSession
    var onStopRecording: (() -> Void)? = nil

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.title)
                    .fontWeight(.medium)
                Text(session.date, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if session.status == .recording, let stop = onStopRecording {
                Button("Stop", action: stop)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(.red)
                    .accessibilityIdentifier("stopRecordingButton_\(session.id)")
            }
            StatusBadgeView(status: session.status)
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("sessionRow_\(session.id)")
    }
}

struct StatusBadgeView: View {
    let status: SessionStatus

    var body: some View {
        HStack(spacing: 4) {
            if status == .recording {
                Circle()
                    .fill(Color.red)
                    .frame(width: 6, height: 6)
                    .accessibilityIdentifier("recordingIndicator")
            }
            Text(status.rawValue.capitalized)
                .font(.caption2)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(badgeColor.opacity(0.15))
        .foregroundStyle(badgeColor)
        .clipShape(Capsule())
    }

    private var badgeColor: Color {
        switch status {
        case .idle: return .gray
        case .recording: return .red
        case .paused: return .orange
        case .stopped: return .green
        case .failed: return .gray
        }
    }
}

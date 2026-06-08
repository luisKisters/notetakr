import SwiftUI
import NoteTakrCore

struct TodayView: View {
    let sessions: [MeetingSession]
    var nextMeeting: CalendarEvent? = nil
    var onSelectSession: (MeetingSession) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox("Next Meeting") {
                if let meeting = nextMeeting {
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
            .accessibilityIdentifier("nextMeetingGroup")

            if sessions.isEmpty {
                Text("No recordings yet")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
                    .accessibilityIdentifier("noSessionsLabel")
            } else {
                Text("Recent Recordings")
                    .font(.headline)
                    .padding(.top, 4)
                List(sessions) { session in
                    SessionRowView(session: session)
                        .contentShape(Rectangle())
                        .onTapGesture { onSelectSession(session) }
                }
                .listStyle(.plain)
            }
        }
        .padding()
        .frame(minWidth: 300)
    }
}

struct SessionRowView: View {
    let session: MeetingSession

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
            StatusBadgeView(status: session.status)
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("sessionRow_\(session.id)")
    }
}

struct StatusBadgeView: View {
    let status: SessionStatus

    var body: some View {
        Text(status.rawValue.capitalized)
            .font(.caption2)
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

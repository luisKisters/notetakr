import SwiftUI
import NoteTakrCore

/// Calendar tab: upcoming events for the next week, grouped by day, each badged
/// as a Meeting or plain Event with its attendee count.
struct CalendarView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { Task { await model.loadUpcomingEvents() } }
    }

    private var header: some View {
        HStack {
            Text("Upcoming")
                .font(.title2.weight(.semibold))
            Spacer()
            if model.isCalendarLoading {
                ProgressView().controlSize(.small)
            }
            Button {
                Task { await model.loadUpcomingEvents() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .controlSize(.small)
            .accessibilityIdentifier("calendarRefreshButton")
        }
        .padding(16)
    }

    @ViewBuilder
    private var content: some View {
        if !model.calendarAuthorized {
            grantAccess
        } else if model.upcomingEvents.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(groupedEvents, id: \.day) { group in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(group.day, format: .dateTime.weekday(.wide).month().day())
                                .font(.headline)
                                .foregroundStyle(.secondary)
                            ForEach(group.events) { event in
                                CalendarEventRow(event: event)
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
    }

    private var grantAccess: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("Calendar access not granted")
                .foregroundStyle(.secondary)
            Text("Grant Calendar access in Settings to see upcoming meetings.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Button("Open Settings") { model.selectedTab = .settings }
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .accessibilityIdentifier("calendarGrantAccess")
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("No upcoming events")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .accessibilityIdentifier("calendarEmptyState")
    }

    private struct DayGroup: Identifiable {
        let day: Date
        let events: [CalendarEvent]
        var id: Date { day }
    }

    private var groupedEvents: [DayGroup] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: model.upcomingEvents) { event in
            calendar.startOfDay(for: event.startDate)
        }
        return groups.keys.sorted().map { day in
            DayGroup(day: day, events: groups[day]!.sorted { $0.startDate < $1.startDate })
        }
    }
}

struct CalendarEventRow: View {
    let event: CalendarEvent

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(event.startDate, style: .time)
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(event.title)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    badge
                }
                if !event.attendees.isEmpty {
                    Label(
                        "^[\(event.attendees.count) attendee](inflect: true)",
                        systemImage: "person.2"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var isMeeting: Bool { MeetingDetector.isMeeting(event) }

    private var badge: some View {
        Text(isMeeting ? "Meeting" : "Event")
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background((isMeeting ? Color.accentColor : Color.secondary).opacity(0.15))
            .foregroundStyle(isMeeting ? Color.accentColor : Color.secondary)
            .clipShape(Capsule())
            .accessibilityIdentifier(isMeeting ? "eventBadge_meeting" : "eventBadge_event")
    }
}

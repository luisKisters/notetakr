import SwiftUI
import NoteTakrCore

/// Detail view for one session inside the main window. Title/notes are edited
/// through a local draft (persisted on change); transcript and status are read
/// live from the model so automatic transcription appears as it completes.
struct SessionDetailPane: View {
    @EnvironmentObject var model: AppModel
    let sessionID: UUID

    @State private var draft: MeetingSession?

    private var session: MeetingSession? { model.session(for: sessionID) }
    private var state: TranscriptionState { model.transcriptionState(for: sessionID) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let session {
                    header(session)
                    Divider()
                    if !session.audioSourceStatuses.isEmpty {
                        AudioSourceStatusSection(statuses: session.audioSourceStatuses)
                    }
                    calendarSection(session)
                    transcriptSection(session)
                    summarySection(session)
                    notesSection
                } else {
                    Text("Session unavailable")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            if draft == nil { draft = session }
            Task { await model.loadUpcomingEvents() }
        }
    }

    // MARK: - Header

    @ViewBuilder
    private func header(_ session: MeetingSession) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                TextField("Meeting title", text: titleBinding)
                    .font(.title2.weight(.semibold))
                    .textFieldStyle(.plain)
                    .accessibilityIdentifier("sessionTitleField")
                Text(session.date, style: .date)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            StatusBadgeView(status: session.status)
        }

        if session.status == .recording {
            HStack(spacing: 8) {
                Circle().fill(Color.red).frame(width: 10, height: 10)
                Text("Recording in progress…")
                    .foregroundStyle(.red)
                    .font(.subheadline)
                Spacer()
                Button("Stop Recording") { Task { await model.stopRecording() } }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
            }
            .padding(8)
            .background(Color.red.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Transcript

    @ViewBuilder
    private func transcriptSection(_ session: MeetingSession) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Transcript")
                        .font(.headline)
                    Spacer()
                    transcriptActions(session)
                }

                switch state {
                case .transcribing:
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Transcribing — speaker diarization + vocabulary boosting…")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityIdentifier("transcribingIndicator")
                case .modelUnavailable:
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Transcription model not configured.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Button("Open Settings") { model.selectedTab = .settings }
                            .controlSize(.small)
                    }
                case .failed(let message):
                    Label(message, systemImage: "xmark.circle")
                        .foregroundStyle(.red)
                default:
                    if session.transcriptSegments.isEmpty {
                        Text(session.audioFilePaths.isEmpty
                            ? "Transcript will appear here after recording."
                            : "Preparing transcription…")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(session.transcriptSegments) { segment in
                            TranscriptSegmentRow(segment: segment)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }

    @ViewBuilder
    private func transcriptActions(_ session: MeetingSession) -> some View {
        if !session.audioFilePaths.isEmpty {
            HStack(spacing: 8) {
                if !session.transcriptSegments.isEmpty {
                    Button("Open Note") { model.openNote(for: session) }
                        .controlSize(.small)
                }
                Button {
                    model.retranscribe(session)
                } label: {
                    Label("Transcribe again", systemImage: "arrow.clockwise")
                }
                .controlSize(.small)
                .disabled(state == .transcribing)
                .accessibilityIdentifier("retranscribeButton")
            }
        }
    }

    // MARK: - Summary

    private var summaryState: SummarizationState { model.summarizationState(for: sessionID) }

    @ViewBuilder
    private func summarySection(_ session: MeetingSession) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Summary")
                        .font(.headline)
                    Spacer()
                    if !session.transcriptSegments.isEmpty {
                        Button {
                            Task { await model.summarize(session) }
                        } label: {
                            Label(
                                session.summary == nil ? "Summarize" : "Summarize again",
                                systemImage: "sparkles"
                            )
                        }
                        .controlSize(.small)
                        .disabled(summaryState == .summarizing)
                        .accessibilityIdentifier("summarizeButton")
                    }
                }

                switch summaryState {
                case .summarizing:
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Summarizing with OpenRouter…")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityIdentifier("summarizingIndicator")
                case .noAPIKey:
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Add an OpenRouter API key to enable summaries.", systemImage: "key")
                            .foregroundStyle(.orange)
                        Button("Open Settings") { model.selectedTab = .settings }
                            .controlSize(.small)
                    }
                case .failed(let message):
                    Label(message, systemImage: "xmark.circle")
                        .foregroundStyle(.red)
                default:
                    if let summary = session.summary, !summary.isEmpty {
                        Text(summary)
                            .font(.body)
                            .textSelection(.enabled)
                            .accessibilityIdentifier("summaryText")
                    } else {
                        Text(session.transcriptSegments.isEmpty
                            ? "A summary will appear here after transcription."
                            : "No summary yet.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }

    // MARK: - Calendar event

    @ViewBuilder
    private func calendarSection(_ session: MeetingSession) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Calendar Event")
                        .font(.headline)
                    Spacer()
                    eventLinkMenu(session)
                }

                if let title = session.linkedEventTitle {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                            .foregroundStyle(.secondary)
                        Text(title)
                            .fontWeight(.medium)
                        Spacer()
                        Button("Unlink") { model.unlinkEvent(from: session) }
                            .controlSize(.small)
                            .accessibilityIdentifier("unlinkEventButton")
                    }
                    if !session.participants.isEmpty {
                        Divider()
                        Text("Participants")
                            .font(.subheadline.weight(.medium))
                        ForEach(session.participants) { participant in
                            VStack(alignment: .leading, spacing: 1) {
                                Text(participant.name)
                                if let email = participant.email, !email.isEmpty {
                                    Text(email)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } else {
                    if let suggestion = suggestedEvent(for: session) {
                        Button {
                            model.linkEvent(suggestion, to: session)
                        } label: {
                            Label("Link suggested: \(suggestion.title)", systemImage: "wand.and.stars")
                        }
                        .controlSize(.small)
                        .accessibilityIdentifier("linkSuggestedEventButton")
                    } else {
                        Text("Link a calendar event to attach participants.")
                            .foregroundStyle(.secondary)
                            .font(.callout)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }

    @ViewBuilder
    private func eventLinkMenu(_ session: MeetingSession) -> some View {
        Menu {
            let nearby = model.eventsNear(session.date)
            if !nearby.isEmpty {
                Section("Near this recording") {
                    ForEach(nearby) { event in
                        Button(eventLabel(event)) { model.linkEvent(event, to: session) }
                    }
                }
            }
            if !model.upcomingEvents.isEmpty {
                Section("Upcoming") {
                    ForEach(model.upcomingEvents) { event in
                        Button(eventLabel(event)) { model.linkEvent(event, to: session) }
                    }
                }
            } else {
                Text("No events available")
            }
        } label: {
            Label(session.linkedEventID == nil ? "Link Event" : "Change", systemImage: "calendar.badge.plus")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityIdentifier("linkEventMenu")
    }

    /// The next upcoming meeting, suggested when a session has no linked event.
    private func suggestedEvent(for session: MeetingSession) -> CalendarEvent? {
        if let next = model.nextMeeting,
           model.eventsNear(session.date).contains(where: { $0.id == next.id }) {
            return next
        }
        return model.eventsNear(session.date).first
    }

    private func eventLabel(_ event: CalendarEvent) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE h:mm a"
        return "\(formatter.string(from: event.startDate)) — \(event.title)"
    }

    // MARK: - Notes

    private var notesSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                Text("Personal Notes")
                    .font(.headline)
                TextEditor(text: notesBinding)
                    .frame(minHeight: 100)
                    .font(.body)
                    .accessibilityIdentifier("personalNotesEditor")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }

    // MARK: - Bindings (edit local draft, persist on change)

    private var titleBinding: Binding<String> {
        Binding(
            get: { draft?.title ?? session?.title ?? "" },
            set: { newValue in
                guard var d = draft ?? session else { return }
                d.title = newValue
                draft = d
                model.persist(d)
            }
        )
    }

    private var notesBinding: Binding<String> {
        Binding(
            get: { draft?.personalNotes ?? session?.personalNotes ?? "" },
            set: { newValue in
                guard var d = draft ?? session else { return }
                d.personalNotes = newValue
                draft = d
                model.persist(d)
            }
        )
    }
}

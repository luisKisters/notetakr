import SwiftUI
import NoteTakrCore

struct SessionDetailView: View {
    @Binding var session: MeetingSession
    var isActiveRecording: Bool = false
    var onStopRecording: (() -> Void)? = nil
    var onTranscribe: (() -> Void)? = nil
    var onGenerateNote: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Meeting title", text: $session.title)
                        .font(.title2.weight(.semibold))
                        .accessibilityIdentifier("sessionTitleField")
                    Text(session.date, style: .date)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusBadgeView(status: session.status)
                    .accessibilityIdentifier("sessionStatusBadge")
            }

            if isActiveRecording {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 10, height: 10)
                        .accessibilityIdentifier("activeRecordingDot")
                    Text("Recording in progress…")
                        .foregroundStyle(.red)
                        .font(.subheadline)
                    Spacer()
                    if let stop = onStopRecording {
                        Button("Stop Recording", action: stop)
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                            .accessibilityIdentifier("stopRecordingDetailButton")
                    }
                }
                .padding(8)
                .background(Color.red.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Divider()

            GroupBox("Transcript") {
                if session.transcriptSegments.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Transcript will appear here after recording.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("transcriptPlaceholder")
                        if !session.audioFilePaths.isEmpty, let transcribe = onTranscribe {
                            Button("Transcribe Audio", action: transcribe)
                                .accessibilityIdentifier("transcribeButton")
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 8) {
                                ForEach(session.transcriptSegments) { segment in
                                    TranscriptSegmentRow(segment: segment)
                                }
                            }
                        }
                        .frame(maxHeight: 200)
                        if let generate = onGenerateNote {
                            Button("Generate Note…", action: generate)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .accessibilityIdentifier("generateNoteButton")
                        }
                    }
                }
            }

            GroupBox("Personal Notes") {
                TextEditor(text: $session.personalNotes)
                    .frame(minHeight: 80)
                    .accessibilityIdentifier("personalNotesEditor")
            }

            if !session.audioFilePaths.isEmpty {
                GroupBox("Audio Files") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(session.audioFilePaths, id: \.self) { path in
                            Text(URL(fileURLWithPath: path).lastPathComponent)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("audioFilesList")
                }
            }

            Spacer()
        }
        .padding()
        .frame(minWidth: 400)
    }
}

struct TranscriptSegmentRow: View {
    let segment: TranscriptSegment

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(formattedTimestamp)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                if let speaker = segment.speaker {
                    Text(speaker)
                        .font(.caption.weight(.medium))
                }
                Text(segment.text)
                    .font(.body)
            }
        }
    }

    private var formattedTimestamp: String {
        let total = Int(segment.timestamp)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

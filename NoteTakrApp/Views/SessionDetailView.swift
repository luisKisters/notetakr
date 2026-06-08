import SwiftUI
import NoteTakrCore

struct SessionDetailView: View {
    @Binding var session: MeetingSession
    var isActiveRecording: Bool = false
    var onStopRecording: (() -> Void)? = nil
    var onTranscribe: (() -> Void)? = nil
    var onGenerateNote: (() -> Void)? = nil
    @ObservedObject var transcriptionCoordinator: TranscriptionCoordinator

    init(
        session: Binding<MeetingSession>,
        isActiveRecording: Bool = false,
        onStopRecording: (() -> Void)? = nil,
        onTranscribe: (() -> Void)? = nil,
        onGenerateNote: (() -> Void)? = nil,
        transcriptionCoordinator: TranscriptionCoordinator = TranscriptionCoordinator()
    ) {
        self._session = session
        self.isActiveRecording = isActiveRecording
        self.onStopRecording = onStopRecording
        self.onTranscribe = onTranscribe
        self.onGenerateNote = onGenerateNote
        self.transcriptionCoordinator = transcriptionCoordinator
    }

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

            if !session.audioSourceStatuses.isEmpty {
                AudioSourceStatusSection(statuses: session.audioSourceStatuses)
            } else if !session.audioFilePaths.isEmpty {
                // Fallback for sessions loaded from disk before source statuses were introduced.
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

            GroupBox("Transcript") {
                if session.transcriptSegments.isEmpty {
                    transcriptEmptyContent
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

            Spacer()
        }
        .padding()
        .frame(minWidth: 400)
    }

    @ViewBuilder
    private var transcriptEmptyContent: some View {
        switch transcriptionCoordinator.state {
        case .transcribing:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Transcribing…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("transcribingIndicator")
        case .modelUnavailable:
            VStack(alignment: .leading, spacing: 6) {
                Label("Transcription model not available", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("transcriptionModelUnavailable")
                Text("To enable local transcription, download a Parakeet model to:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("~/Library/Application Support/NoteTakr/Models/parakeet-tdt-0.6b.bin")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .failed(let message):
            Label(message, systemImage: "xmark.circle")
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("transcriptionFailed")
        default:
            VStack(alignment: .leading, spacing: 8) {
                Text("Transcript will appear here after recording.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("transcriptPlaceholder")
                if !session.audioFilePaths.isEmpty, let transcribe = onTranscribe {
                    Button("Transcribe Audio", action: transcribe)
                        .accessibilityIdentifier("transcribeButton")
                        .disabled(transcriptionCoordinator.state == .transcribing)
                }
            }
        }
    }
}

// MARK: - Audio Source Status Section

struct AudioSourceStatusSection: View {
    let statuses: [AudioSourceStatus]

    var body: some View {
        GroupBox("Audio Sources") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(statuses) { status in
                    AudioSourceRow(status: status)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("audioSourceStatusSection")
        }
    }
}

struct AudioSourceRow: View {
    let status: AudioSourceStatus

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: status.isPresent ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(status.isPresent ? .green : .red)
                .accessibilityIdentifier(
                    status.isPresent
                        ? "audioSourcePresent_\(status.source.rawValue)"
                        : "audioSourceMissing_\(status.source.rawValue)"
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(status.source.displayName)
                    .font(.subheadline.weight(.medium))
                if status.isPresent {
                    Text(captureDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(missingDetail)
                        .font(.caption)
                        .foregroundStyle(.red.opacity(0.8))
                        .accessibilityIdentifier("audioSourceMissingReason_\(status.source.rawValue)")
                }
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }

    private var captureDetail: String {
        var parts: [String] = []
        if let dur = status.durationSeconds {
            let mins = Int(dur) / 60
            let secs = Int(dur) % 60
            parts.append(String(format: "%d:%02d", mins, secs))
        }
        if let bytes = status.fileSizeBytes {
            parts.append(formatBytes(bytes))
        }
        return parts.isEmpty ? "Captured" : parts.joined(separator: " · ")
    }

    private var missingDetail: String {
        status.missingReason ?? "Not captured"
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let kb = Double(bytes) / 1024
        if kb < 1024 {
            return String(format: "%.0f KB", kb)
        }
        let mb = kb / 1024
        return String(format: "%.1f MB", mb)
    }
}

// MARK: - Transcript

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

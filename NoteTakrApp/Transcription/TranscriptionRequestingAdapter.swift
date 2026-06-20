import Foundation
import NoteTakrKit
import NoteTakrCore

/// Bridges Kit's TranscriptionRequesting to Core's FluidAudio transcription pipeline.
/// Called by RecordingNoteBridge when a recording stops and transcribe=true.
final class TranscriptionRequestingAdapter: TranscriptionRequesting, @unchecked Sendable {
    private let appModel: AppModel

    init(appModel: AppModel) {
        self.appModel = appModel
    }

    func transcribe(
        noteID: String,
        language: TranscribeLanguage,
        vocabulary: [String]
    ) async throws -> [RawSegment] {
        let segments = try await appModel.transcribeForRecordingBridge(
            noteID: noteID,
            vocabulary: vocabulary
        )
        return segments.map { seg in
            RawSegment(speaker: seg.speaker, timestamp: seg.timestamp, text: seg.text)
        }
    }
}

// MARK: - Manual "Generate transcript" support

/// Lets the Transcript tab re-run transcription on demand (e.g. for a recording
/// that was captured but never transcribed). Routes through the same AppModel path.
extension TranscriptionRequestingAdapter: TranscriptGenerating {
    func generate(for noteID: String) async throws -> [RawSegment] {
        try await transcribe(noteID: noteID, language: .auto, vocabulary: [])
    }
}

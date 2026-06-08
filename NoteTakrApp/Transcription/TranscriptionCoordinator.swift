import Foundation
import NoteTakrCore

/// Tracks transcription progress for a single session detail window.
/// Published state drives the SessionDetailView loading/error UI.
@MainActor
final class TranscriptionCoordinator: ObservableObject {
    @Published var state: TranscriptionState = .idle

    func transcribe(
        session: MeetingSession,
        service: TranscriptionService,
        vocabulary: [VocabularyEntry]
    ) async -> MeetingSession? {
        state = .transcribing
        do {
            let updated = try await service.transcribe(session: session, vocabulary: vocabulary)
            state = .completed
            return updated
        } catch TranscriptionError.modelUnavailable {
            state = .modelUnavailable
            return nil
        } catch TranscriptionError.audioFileNotFound {
            state = .failed("Audio file not found")
            return nil
        } catch {
            state = .failed(error.localizedDescription)
            return nil
        }
    }
}

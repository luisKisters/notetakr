import Foundation
import NoteTakrCore

// Skeleton for Parakeet local transcription via FluidAudio.
// Model downloading and real inference are disabled in automated CI.
// Verified only on a physical Mac with FluidAudio installed and a model downloaded.
final class FluidAudioAdapter: TranscriptionEngine, @unchecked Sendable {
    private let modelDirectory: URL

    init(modelDirectory: URL) {
        self.modelDirectory = modelDirectory
    }

    func transcribe(audioURL: URL, vocabulary: [VocabularyEntry]) async throws -> [TranscriptSegment] {
        guard ProcessInfo.processInfo.environment["CI"] == nil else {
            throw TranscriptionError.modelUnavailable
        }
        let modelPath = modelDirectory.appendingPathComponent("parakeet-tdt-0.6b.bin")
        guard FileManager.default.fileExists(atPath: modelPath.path) else {
            throw TranscriptionError.modelUnavailable
        }
        // FluidAudio inference would be invoked here once the package is linked.
        // Returns empty result until the FluidAudio package is available.
        return []
    }
}

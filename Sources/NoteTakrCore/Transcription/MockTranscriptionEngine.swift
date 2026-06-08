import Foundation

public final class MockTranscriptionEngine: TranscriptionEngine, @unchecked Sendable {
    public var fixtureSegments: [TranscriptSegment]
    public var shouldFail: Bool = false
    public private(set) var transcribeCallCount: Int = 0
    public private(set) var lastVocabulary: [VocabularyEntry] = []

    public init(fixtureSegments: [TranscriptSegment] = MockTranscriptionEngine.defaultFixture()) {
        self.fixtureSegments = fixtureSegments
    }

    public func transcribe(audioURL: URL, vocabulary: [VocabularyEntry]) async throws -> [TranscriptSegment] {
        transcribeCallCount += 1
        lastVocabulary = vocabulary
        if shouldFail {
            throw TranscriptionError.transcriptionFailed("mock failure")
        }
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw TranscriptionError.audioFileNotFound
        }
        return fixtureSegments
    }

    public static func defaultFixture() -> [TranscriptSegment] {
        [
            TranscriptSegment(timestamp: 0, speaker: "Alice", text: "Let's get started."),
            TranscriptSegment(timestamp: 5, speaker: "Bob", text: "Agreed, let's dive in."),
            TranscriptSegment(timestamp: 12, text: "Discussion of requirements.")
        ]
    }
}

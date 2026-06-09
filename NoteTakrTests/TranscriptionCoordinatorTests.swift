import XCTest
import NoteTakrCore
@testable import NoteTakr

@MainActor
final class TranscriptionCoordinatorTests: XCTestCase {

    func testModelUnavailableState() async throws {
        let fixture = try makeFixture()
        let service = TranscriptionService(
            engine: CoordinatorFakeEngine(error: TranscriptionError.modelUnavailable),
            store: fixture.store
        )
        let coordinator = TranscriptionCoordinator()

        let updated = await coordinator.transcribe(
            session: fixture.session,
            service: service,
            vocabulary: []
        )

        XCTAssertNil(updated)
        XCTAssertEqual(coordinator.state, .modelUnavailable)
    }

    func testFailedState() async throws {
        let fixture = try makeFixture()
        let service = TranscriptionService(
            engine: CoordinatorFakeEngine(error: TranscriptionError.transcriptionFailed("decode failed")),
            store: fixture.store
        )
        let coordinator = TranscriptionCoordinator()

        let updated = await coordinator.transcribe(
            session: fixture.session,
            service: service,
            vocabulary: []
        )

        XCTAssertNil(updated)
        XCTAssertEqual(coordinator.state, .failed("decode failed"))
    }

    func testCompletedState() async throws {
        let fixture = try makeFixture()
        let segment = TranscriptSegment(timestamp: 0, speaker: nil, text: "Done")
        let service = TranscriptionService(
            engine: CoordinatorFakeEngine(segments: [segment]),
            store: fixture.store
        )
        let coordinator = TranscriptionCoordinator()

        let updated = await coordinator.transcribe(
            session: fixture.session,
            service: service,
            vocabulary: []
        )

        XCTAssertEqual(coordinator.state, .completed)
        XCTAssertEqual(updated?.transcriptSegments.count, 1)
        XCTAssertEqual(updated?.transcriptSegments.first?.text, "Done")
    }

    private func makeFixture() throws -> (store: SessionStore, session: MeetingSession) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TranscriptionCoordinatorTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let audioURL = tempDir.appendingPathComponent("audio.wav")
        try Data("fake-audio".utf8).write(to: audioURL)

        let store = SessionStore(baseURL: tempDir)
        var session = MeetingSession(title: "Meeting", date: Date())
        session.audioFilePaths = [audioURL.path]
        try store.save(session)
        return (store, session)
    }
}

private final class CoordinatorFakeEngine: TranscriptionEngine, @unchecked Sendable {
    private let segments: [TranscriptSegment]
    private let error: Error?

    init(segments: [TranscriptSegment] = [], error: Error? = nil) {
        self.segments = segments
        self.error = error
    }

    func transcribe(audioURL: URL, vocabulary: [VocabularyEntry]) async throws -> [TranscriptSegment] {
        if let error {
            throw error
        }
        return segments
    }
}

import XCTest
@testable import NoteTakrCore

final class TranscriptionStateTests: XCTestCase {

    func testEquality() {
        XCTAssertEqual(TranscriptionState.idle, .idle)
        XCTAssertEqual(TranscriptionState.transcribing, .transcribing)
        XCTAssertEqual(TranscriptionState.completed, .completed)
        XCTAssertEqual(TranscriptionState.modelUnavailable, .modelUnavailable)
        XCTAssertEqual(TranscriptionState.failed("oops"), .failed("oops"))
    }

    func testInequality() {
        XCTAssertNotEqual(TranscriptionState.idle, .transcribing)
        XCTAssertNotEqual(TranscriptionState.failed("a"), .failed("b"))
        XCTAssertNotEqual(TranscriptionState.modelUnavailable, .completed)
    }
}

final class TranscriptionServiceTests: XCTestCase {

    private var tempDir: URL!
    private var store: SessionStore!
    private var audioFile: URL!

    override func setUp() {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TranscriptionServiceTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = SessionStore(baseURL: tempDir)
        audioFile = tempDir.appendingPathComponent("test.m4a")
        try? Data("fake-audio".utf8).write(to: audioFile)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testTranscribePersistsSegments() async throws {
        let engine = MockTranscriptionEngine()
        let service = TranscriptionService(engine: engine, store: store)
        var session = MeetingSession(title: "Meeting", date: Date())
        session.audioFilePaths = [audioFile.path]
        try store.save(session)

        let updated = try await service.transcribe(session: session, vocabulary: [])

        XCTAssertEqual(updated.transcriptSegments.count, 3)
        XCTAssertEqual(updated.transcriptSegments[0].speaker, "Alice")

        let reloaded = try store.load(id: session.id)
        XCTAssertEqual(reloaded?.transcriptSegments.count, 3)
    }

    func testTranscribePassesVocabulary() async throws {
        let engine = MockTranscriptionEngine()
        let service = TranscriptionService(engine: engine, store: store)
        var session = MeetingSession(title: "Meeting", date: Date())
        session.audioFilePaths = [audioFile.path]
        try store.save(session)

        let vocab = [VocabularyEntry(phrase: "NoteTakr", isEnabled: true, boostingWeight: 2.0)]
        _ = try await service.transcribe(session: session, vocabulary: vocab)

        XCTAssertEqual(engine.lastVocabulary.count, 1)
        XCTAssertEqual(engine.lastVocabulary[0].phrase, "NoteTakr")
    }

    func testTranscribeThrowsWhenNoAudioFiles() async {
        let engine = MockTranscriptionEngine()
        let service = TranscriptionService(engine: engine, store: store)
        let session = MeetingSession(title: "Meeting", date: Date())

        do {
            _ = try await service.transcribe(session: session, vocabulary: [])
            XCTFail("Expected audioFileNotFound")
        } catch TranscriptionError.audioFileNotFound {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testTranscribeThrowsWhenAudioFileMissing() async throws {
        let engine = MockTranscriptionEngine()
        let service = TranscriptionService(engine: engine, store: store)
        var session = MeetingSession(title: "Meeting", date: Date())
        session.audioFilePaths = ["/nonexistent/audio.m4a"]
        try store.save(session)

        do {
            _ = try await service.transcribe(session: session, vocabulary: [])
            XCTFail("Expected audioFileNotFound")
        } catch TranscriptionError.audioFileNotFound {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testTranscribeThrowsWhenEngineFails() async throws {
        let engine = MockTranscriptionEngine()
        engine.shouldFail = true
        let service = TranscriptionService(engine: engine, store: store)
        var session = MeetingSession(title: "Meeting", date: Date())
        session.audioFilePaths = [audioFile.path]
        try store.save(session)

        do {
            _ = try await service.transcribe(session: session, vocabulary: [])
            XCTFail("Expected transcriptionFailed")
        } catch TranscriptionError.transcriptionFailed {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testTranscribeWithModelUnavailableError() async throws {
        final class UnavailableEngine: TranscriptionEngine, @unchecked Sendable {
            func transcribe(audioURL: URL, vocabulary: [VocabularyEntry]) async throws -> [TranscriptSegment] {
                throw TranscriptionError.modelUnavailable
            }
        }
        let service = TranscriptionService(engine: UnavailableEngine(), store: store)
        var session = MeetingSession(title: "Meeting", date: Date())
        session.audioFilePaths = [audioFile.path]
        try store.save(session)

        do {
            _ = try await service.transcribe(session: session, vocabulary: [])
            XCTFail("Expected modelUnavailable")
        } catch TranscriptionError.modelUnavailable {
            // Expected — caller must handle this and show the unavailable state
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testTranscribedSessionReturnedWithSegments() async throws {
        let segments = [
            TranscriptSegment(timestamp: 0, speaker: "A", text: "Hello"),
            TranscriptSegment(timestamp: 10, text: "Discussion")
        ]
        let engine = MockTranscriptionEngine(fixtureSegments: segments)
        let service = TranscriptionService(engine: engine, store: store)
        var session = MeetingSession(title: "Meeting", date: Date())
        session.audioFilePaths = [audioFile.path]
        try store.save(session)

        let updated = try await service.transcribe(session: session, vocabulary: [])

        XCTAssertEqual(updated.transcriptSegments.count, 2)
        XCTAssertEqual(updated.transcriptSegments[0].text, "Hello")
        XCTAssertEqual(updated.transcriptSegments[1].timestamp, 10)
    }
}

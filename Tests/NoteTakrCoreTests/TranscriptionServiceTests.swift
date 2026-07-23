import XCTest
@testable import NoteTakrCore
import NoteTakrKit

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

    func testTranscribeMarksSessionDirtyAfterPersistingTranscript() async throws {
        let engine = MockTranscriptionEngine()
        let dirty = DirtyIDRecorder()
        let service = TranscriptionService(
            engine: engine,
            store: store,
            markDirty: { dirty.record($0) }
        )
        var session = MeetingSession(title: "Meeting", date: Date())
        session.audioFilePaths = [audioFile.path]
        try store.save(session)

        let updated = try await service.transcribe(session: session, vocabulary: [])
        let reloaded = try XCTUnwrap(store.load(id: session.id))

        XCTAssertEqual(reloaded.transcriptSegments, updated.transcriptSegments)
        XCTAssertEqual(dirty.ids, [session.id.uuidString])
    }

    func testTranscribePreservesNoteFrontmatterBeforeMarkingDirty() async throws {
        let engine = MockTranscriptionEngine()
        let noteStore = NoteStore(root: tempDir)
        let snapshots = DirtyNoteSnapshotRecorder()
        let service = TranscriptionService(
            engine: engine,
            store: store,
            markDirty: { id in
                let loadedNote: MeetingNote?
                do {
                    loadedNote = try noteStore.load(id: id)
                } catch {
                    loadedNote = nil
                }
                snapshots.record(
                    localOnly: loadedNote?.localOnly,
                    crmPushOptOut: loadedNote?.crmPushOptOut
                )
            }
        )
        let id = UUID(uuidString: "67676767-6767-6767-6767-676767676767")!
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        var session = MeetingSession(id: id, title: "Protected Meeting", date: date)
        session.audioFilePaths = [audioFile.path]
        try store.save(session)
        try noteStore.save(MeetingNote(
            id: id.uuidString,
            title: "Protected Meeting",
            date: date,
            participants: [NoteTakrKit.Participant(name: "Ada", email: "ada@example.test", crm: "crm-1")],
            localOnly: true,
            crmPushOptOut: true,
            body: "private draft"
        ))

        _ = try await service.transcribe(session: session, vocabulary: [])

        XCTAssertEqual(snapshots.localOnlyValues, [true])
        XCTAssertEqual(snapshots.crmPushOptOutValues, [true])
        let reloadedNote = try XCTUnwrap(noteStore.load(id: id.uuidString))
        XCTAssertEqual(reloadedNote.localOnly, true)
        XCTAssertEqual(reloadedNote.crmPushOptOut, true)
        XCTAssertEqual(reloadedNote.participants.first?.crm, "crm-1")
        XCTAssertTrue(reloadedNote.body.contains("## Transcript"))
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

    func testNoteGeneratedAfterTranscription() async throws {
        let engine = MockTranscriptionEngine()
        let service = TranscriptionService(engine: engine, store: store)
        var session = MeetingSession(title: "Auto Note Meeting", date: Date())
        session.audioFilePaths = [audioFile.path]
        try store.save(session)

        _ = try await service.transcribe(session: session, vocabulary: [])

        let noteURL = store.sessionURL(for: session).appendingPathComponent("note.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: noteURL.path), "note.md should be generated after transcription")
        let content = try String(contentsOf: noteURL, encoding: .utf8)
        XCTAssertTrue(content.contains("# Auto Note Meeting"))
        XCTAssertTrue(content.contains("## Transcript"))
    }

    func testNoteContainsTranscriptContent() async throws {
        let segments = [TranscriptSegment(timestamp: 0, speaker: "Alice", text: "Auto note text")]
        let engine = MockTranscriptionEngine(fixtureSegments: segments)
        let service = TranscriptionService(engine: engine, store: store)
        var session = MeetingSession(title: "Content Check", date: Date())
        session.audioFilePaths = [audioFile.path]
        try store.save(session)

        _ = try await service.transcribe(session: session, vocabulary: [])

        let noteURL = store.sessionURL(for: session).appendingPathComponent("note.md")
        let content = try String(contentsOf: noteURL, encoding: .utf8)
        XCTAssertTrue(content.contains("Auto note text"))
        XCTAssertTrue(content.contains("Alice"))
    }

    func testInPersonSessionSendsOnlyMicrophoneSourceToTranscription() async throws {
        let engine = SourceCapturingTranscriptionEngine()
        let service = TranscriptionService(engine: engine, store: store)
        var session = MeetingSession(title: "In Person", date: Date(), inPerson: true)
        let mic = tempDir.appendingPathComponent("microphone.m4a")
        let system = tempDir.appendingPathComponent("system-audio.m4a")
        try Data("mic".utf8).write(to: mic)
        try Data("system".utf8).write(to: system)
        session.audioFilePaths = [mic.path, system.path]
        try store.save(session)

        _ = try await service.transcribe(session: session, vocabulary: [])

        XCTAssertEqual(engine.lastSources.map(\.role), [.microphone])
    }

    func testDisabledMicrophoneSendsOnlySystemAudioSourceToTranscription() async throws {
        let engine = SourceCapturingTranscriptionEngine()
        let service = TranscriptionService(engine: engine, store: store)
        var session = MeetingSession(
            title: "System Only",
            date: Date(),
            microphoneEnabled: false,
            systemAudioEnabled: true
        )
        let mic = tempDir.appendingPathComponent("microphone.m4a")
        let system = tempDir.appendingPathComponent("system-audio.m4a")
        try Data("mic".utf8).write(to: mic)
        try Data("system".utf8).write(to: system)
        session.audioFilePaths = [mic.path, system.path]
        try store.save(session)

        _ = try await service.transcribe(session: session, vocabulary: [])

        XCTAssertEqual(engine.lastSources.map(\.role), [.systemAudio])
    }

    func testRemoteSessionSendsMicrophoneBeforeSystemAudio() async throws {
        let engine = SourceCapturingTranscriptionEngine()
        let service = TranscriptionService(engine: engine, store: store)
        var session = MeetingSession(
            title: "Remote",
            date: Date(),
            microphoneEnabled: true,
            systemAudioEnabled: true
        )
        let mic = tempDir.appendingPathComponent("microphone.m4a")
        let system = tempDir.appendingPathComponent("system-audio.m4a")
        try Data("mic".utf8).write(to: mic)
        try Data("system".utf8).write(to: system)
        session.audioFilePaths = [system.path, mic.path]
        try store.save(session)

        _ = try await service.transcribe(session: session, vocabulary: [])

        XCTAssertEqual(engine.lastSources.map(\.role), [.microphone, .systemAudio])
        XCTAssertEqual(engine.lastSources.map { $0.url.lastPathComponent }, ["microphone.m4a", "system-audio.m4a"])
    }
}

private final class SourceCapturingTranscriptionEngine: TranscriptionEngine, @unchecked Sendable {
    private(set) var lastSources: [TranscriptionSource] = []

    func transcribe(audioURL: URL, vocabulary: [VocabularyEntry]) async throws -> [TranscriptSegment] {
        lastSources = [TranscriptionSource(url: audioURL, role: .microphone)]
        return [TranscriptSegment(timestamp: 0, speaker: "Speaker 1", text: "single")]
    }

    func transcribe(sources: [TranscriptionSource], vocabulary: [VocabularyEntry]) async throws -> [TranscriptSegment] {
        lastSources = sources
        return [TranscriptSegment(timestamp: 0, speaker: "Speaker 1", text: "multi")]
    }
}

private final class DirtyIDRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedIDs: [String] = []

    var ids: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recordedIDs
    }

    func record(_ id: String) {
        lock.lock()
        recordedIDs.append(id)
        lock.unlock()
    }
}

private final class DirtyNoteSnapshotRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedLocalOnlyValues: [Bool?] = []
    private var recordedCrmPushOptOutValues: [Bool?] = []

    var localOnlyValues: [Bool?] {
        lock.lock()
        defer { lock.unlock() }
        return recordedLocalOnlyValues
    }

    var crmPushOptOutValues: [Bool?] {
        lock.lock()
        defer { lock.unlock() }
        return recordedCrmPushOptOutValues
    }

    func record(localOnly: Bool?, crmPushOptOut: Bool?) {
        lock.lock()
        recordedLocalOnlyValues.append(localOnly)
        recordedCrmPushOptOutValues.append(crmPushOptOut)
        lock.unlock()
    }
}

// MARK: - Stale-path regression (title rename moved the session folder)

final class StaleAudioPathTests: XCTestCase {

    private var tempDir: URL!
    private var store: SessionStore!

    override func setUp() {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("StaleAudioPathTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = SessionStore(baseURL: tempDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
    }

    /// Reproduces the real-world bug: recording saves audio under the original
    /// title's folder; renaming the session moves the folder, leaving stored
    /// absolute audioFilePaths stale → transcription used to throw audioFileNotFound.
    func testTranscribeSucceedsAfterTitleRenameMovedFolder() async throws {
        var session = MeetingSession(title: "Meeting Recording", date: Date())
        try store.save(session)
        let originalDir = store.sessionURL(for: session)
        let audio = originalDir.appendingPathComponent("microphone.m4a")
        try Data("fake-audio".utf8).write(to: audio)
        session.audioFilePaths = [audio.path]   // absolute path into the ORIGINAL folder
        try store.save(session)

        // Rename → SessionStore.save moves the folder; old absolute path is now stale.
        session.title = "Untitled meeting"
        try store.save(session)
        XCTAssertFalse(FileManager.default.fileExists(atPath: audio.path),
                       "precondition: original path must be stale after rename")

        let service = TranscriptionService(engine: MockTranscriptionEngine(), store: store)
        let updated = try await service.transcribe(session: session, vocabulary: [])
        XCTAssertFalse(updated.transcriptSegments.isEmpty,
                       "transcription must survive a folder rename")
    }

    /// SessionStore.save must heal stored audio paths when the folder moves.
    func testSaveHealsAudioPathsAfterRename() throws {
        var session = MeetingSession(title: "Original", date: Date())
        try store.save(session)
        let originalDir = store.sessionURL(for: session)
        let audio = originalDir.appendingPathComponent("microphone.m4a")
        try Data("fake-audio".utf8).write(to: audio)
        session.audioFilePaths = [audio.path]
        try store.save(session)

        session.title = "Renamed"
        try store.save(session)

        let reloaded = try XCTUnwrap(store.load(id: session.id))
        let healedPath = try XCTUnwrap(reloaded.audioFilePaths.first)
        XCTAssertTrue(FileManager.default.fileExists(atPath: healedPath),
                      "saved audioFilePaths must point at the moved file, got \(healedPath)")
    }

    /// The static source-builder falls back to the session dir by filename.
    func testTranscriptionSourcesFallBackToSessionDir() throws {
        var session = MeetingSession(title: "T", date: Date())
        try store.save(session)
        let dir = store.sessionURL(for: session)
        try Data("fake-audio".utf8).write(to: dir.appendingPathComponent("microphone.m4a"))
        session.audioFilePaths = ["/nonexistent/old-folder/microphone.m4a"]

        let sources = TranscriptionService.transcriptionSources(for: session, sessionDir: dir)
        XCTAssertEqual(sources.count, 1)
        XCTAssertEqual(sources.first?.url.lastPathComponent, "microphone.m4a")
        XCTAssertEqual(sources.first?.role, .microphone)
    }
}

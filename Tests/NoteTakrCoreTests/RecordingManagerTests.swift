import XCTest
@testable import NoteTakrCore

final class RecordingManagerTests: XCTestCase {
    private var tempDir: URL!
    private var store: SessionStore!
    private var recorder: MockAudioRecorder!
    private var manager: RecordingManager!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RecordingManagerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = SessionStore(baseURL: tempDir)
        recorder = MockAudioRecorder()
        manager = RecordingManager(store: store, recorder: recorder)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Start

    func testStartRecordingCreatesSessionInRecordingState() async throws {
        let session = try await manager.startRecording(title: "Standup")
        XCTAssertEqual(session.status, .recording)
        XCTAssertEqual(session.title, "Standup")
    }

    func testStartRecordingSavesSessionToDisk() async throws {
        let session = try await manager.startRecording(title: "Design Review")
        let loaded = try store.load(id: session.id)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.status, .recording)
    }

    func testStartRecordingCallsRecorder() async throws {
        _ = try await manager.startRecording(title: "Test")
        XCTAssertEqual(recorder.startCallCount, 1)
        XCTAssertTrue(recorder.isRecording)
    }

    func testStartRecordingSetsActiveSession() async throws {
        let session = try await manager.startRecording(title: "Active")
        XCTAssertNotNil(manager.activeSession)
        XCTAssertEqual(manager.activeSession?.id, session.id)
    }

    func testStartRecordingReusesProvidedSessionID() async throws {
        let id = UUID()
        let existing = MeetingSession(
            id: id,
            title: "Existing Meeting",
            date: Date(timeIntervalSince1970: 1_800_000_000),
            status: .idle,
            audioFilePaths: ["/tmp/old-audio.wav"]
        )
        try store.save(existing)

        let started = try await manager.startRecording(session: existing)

        XCTAssertEqual(started.id, id)
        XCTAssertEqual(started.status, .recording)
        XCTAssertEqual(try store.loadAll().count, 1, "Starting a provided session must not create a second note/session")
        XCTAssertEqual(try store.load(id: id)?.status, .recording)
        XCTAssertEqual(try store.load(id: id)?.audioFilePaths, [], "Old audio paths should not appear while a new recording is in progress")
    }

    func testStartRecordingWhenAlreadyRecordingThrows() async throws {
        _ = try await manager.startRecording(title: "First")
        do {
            _ = try await manager.startRecording(title: "Second")
            XCTFail("Expected alreadyRecording error")
        } catch RecordingManagerError.alreadyRecording {
            // expected
        }
    }

    func testStartRecordingFailureSavesSessionAsFailed() async throws {
        recorder.shouldFailOnStart = true
        do {
            _ = try await manager.startRecording(title: "Will Fail")
            XCTFail("Expected error")
        } catch {
            let sessions = try store.loadAll()
            XCTAssertEqual(sessions.count, 1)
            XCTAssertEqual(sessions.first?.status, .failed)
        }
    }

    func testStartRecordingFailureClearsActiveSession() async throws {
        recorder.shouldFailOnStart = true
        _ = try? await manager.startRecording(title: "Will Fail")
        XCTAssertNil(manager.activeSession)
    }

    // MARK: - Stop

    func testStopRecordingTransitionsToStopped() async throws {
        _ = try await manager.startRecording(title: "Meeting")
        let stopped = try await manager.stopRecording()
        XCTAssertEqual(stopped.status, .stopped)
    }

    func testStopRecordingCallsRecorder() async throws {
        _ = try await manager.startRecording(title: "Meeting")
        _ = try await manager.stopRecording()
        XCTAssertEqual(recorder.stopCallCount, 1)
        XCTAssertFalse(recorder.isRecording)
    }

    func testStopRecordingSavesAudioFilePaths() async throws {
        let session = try await manager.startRecording(title: "With Audio")
        let stopped = try await manager.stopRecording()
        XCTAssertEqual(stopped.audioFilePaths.count, 2)
        let loaded = try store.load(id: session.id)
        XCTAssertEqual(loaded?.audioFilePaths.count, 2)
    }

    func testStopRecordingWithInPersonSessionSkipsSystemAudio() async throws {
        let input = MeetingSession(
            title: "In Person",
            date: Date(),
            inPerson: true,
            microphoneEnabled: true,
            systemAudioEnabled: true
        )

        _ = try await manager.startRecording(session: input)
        XCTAssertEqual(
            recorder.lastStartOptions,
            AudioRecordingOptions(microphoneEnabled: true, systemAudioEnabled: false)
        )
        XCTAssertEqual(manager.activeSession?.systemAudioEnabled, false)
        let stopped = try await manager.stopRecording()

        XCTAssertEqual(stopped.audioFilePaths.count, 1)
        XCTAssertTrue(stopped.audioFilePaths[0].hasSuffix("microphone.wav"))
        XCTAssertEqual(
            stopped.audioSourceStatuses.first { $0.source == .systemAudio }?.missingReason,
            "System audio disabled"
        )
        XCTAssertFalse(stopped.systemAudioEnabled)
    }

    func testStopRecordingWithMicDisabledCapturesOnlySystemAudio() async throws {
        let input = MeetingSession(
            title: "System Only",
            date: Date(),
            microphoneEnabled: false,
            systemAudioEnabled: true
        )

        _ = try await manager.startRecording(session: input)
        let stopped = try await manager.stopRecording()

        XCTAssertEqual(stopped.audioFilePaths.count, 1)
        XCTAssertTrue(stopped.audioFilePaths[0].hasSuffix("system-audio.wav"))
        XCTAssertEqual(
            stopped.audioSourceStatuses.first { $0.source == .microphone }?.missingReason,
            "Microphone disabled"
        )
    }

    func testStopRecordingDoesNotRecoverStaleDisabledSystemAudio() async throws {
        let input = MeetingSession(
            title: "Stale Disabled System",
            date: Date(),
            microphoneEnabled: true,
            systemAudioEnabled: false
        )
        let dir = store.sessionURL(for: input)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let staleSystemURL = dir.appendingPathComponent("system-audio.wav")
        try Data(repeating: 7, count: 512).write(to: staleSystemURL)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -120)],
            ofItemAtPath: staleSystemURL.path
        )

        _ = try await manager.startRecording(session: input)
        let stopped = try await manager.stopRecording()

        XCTAssertEqual(stopped.audioFilePaths.count, 1)
        XCTAssertTrue(stopped.audioFilePaths[0].hasSuffix("microphone.wav"))
        let sysStatus = try XCTUnwrap(stopped.audioSourceStatuses.first { $0.source == .systemAudio })
        XCTAssertFalse(sysStatus.isPresent)
        XCTAssertEqual(sysStatus.missingReason, "System audio disabled")
    }

    func testStopRecordingDoesNotRecoverStaleEnabledSystemAudioAfterCaptureFailure() async throws {
        recorder.omitSystemAudio = true
        recorder.mockMissingReasons = ["systemAudio": "Capture start failure"]
        let input = MeetingSession(
            title: "Stale Enabled System",
            date: Date(),
            microphoneEnabled: true,
            systemAudioEnabled: true
        )
        let dir = store.sessionURL(for: input)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let staleSystemURL = dir.appendingPathComponent("system-audio.wav")
        try Data(repeating: 9, count: 512).write(to: staleSystemURL)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -120)],
            ofItemAtPath: staleSystemURL.path
        )

        _ = try await manager.startRecording(session: input)
        let stopped = try await manager.stopRecording()

        XCTAssertEqual(stopped.audioFilePaths.count, 1)
        XCTAssertTrue(stopped.audioFilePaths[0].hasSuffix("microphone.wav"))
        let sysStatus = try XCTUnwrap(stopped.audioSourceStatuses.first { $0.source == .systemAudio })
        XCTAssertFalse(sysStatus.isPresent)
        XCTAssertEqual(sysStatus.missingReason, "Capture start failure")
    }

    func testStartRecordingWithNoEnabledSourcesThrows() async throws {
        let input = MeetingSession(
            title: "No Sources",
            date: Date(),
            microphoneEnabled: false,
            systemAudioEnabled: false
        )

        do {
            _ = try await manager.startRecording(session: input)
            XCTFail("Expected recordingFailed")
        } catch AudioRecorderError.recordingFailed(let reason) {
            XCTAssertEqual(reason, "No audio sources are enabled")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testChangingActiveRecordingToInPersonStopsSystemAudioAndPersistsSession() async throws {
        let started = try await manager.startRecording(session: MeetingSession(
            title: "Moves In Person",
            date: Date(),
            inPerson: false,
            microphoneEnabled: true,
            systemAudioEnabled: true
        ))

        let updated = try await manager.updateActiveRecording(
            inPerson: true,
            options: AudioRecordingOptions(microphoneEnabled: true, systemAudioEnabled: true)
        )

        XCTAssertTrue(updated.inPerson)
        XCTAssertFalse(updated.systemAudioEnabled)
        XCTAssertEqual(
            recorder.lastUpdateOptions,
            AudioRecordingOptions(microphoneEnabled: true, systemAudioEnabled: false)
        )
        let persisted = try XCTUnwrap(store.load(id: started.id))
        XCTAssertTrue(persisted.inPerson)
        XCTAssertFalse(persisted.systemAudioEnabled)

        let stopped = try await manager.stopRecording()
        XCTAssertEqual(stopped.audioFilePaths.count, 1)
        XCTAssertTrue(stopped.audioFilePaths[0].hasSuffix("microphone.wav"))
    }

    func testChangingActiveRecordingBackOnlineResumesConfiguredSystemAudio() async throws {
        _ = try await manager.startRecording(session: MeetingSession(
            title: "Hybrid Meeting",
            date: Date(),
            inPerson: true,
            microphoneEnabled: true,
            systemAudioEnabled: false
        ))

        let updated = try await manager.updateActiveRecording(
            inPerson: false,
            options: AudioRecordingOptions(microphoneEnabled: true, systemAudioEnabled: true)
        )

        XCTAssertFalse(updated.inPerson)
        XCTAssertTrue(updated.systemAudioEnabled)
        XCTAssertEqual(
            recorder.lastUpdateOptions,
            AudioRecordingOptions(microphoneEnabled: true, systemAudioEnabled: true)
        )
    }

    func testStopRecordingCreatesFixtureAudioFiles() async throws {
        _ = try await manager.startRecording(title: "Audio Files")
        let stopped = try await manager.stopRecording()
        for path in stopped.audioFilePaths {
            XCTAssertTrue(FileManager.default.fileExists(atPath: path), "Missing: \(path)")
        }
    }

    func testStopRecordingRecoversAudioFileAfterRecordingFolderMoves() async throws {
        let movingRecorder = MovedFolderAudioRecorder()
        manager = RecordingManager(store: store, recorder: movingRecorder)

        let started = try await manager.startRecording(title: "Original Title")
        var renamed = started
        renamed.title = "Renamed While Recording"
        renamed.status = .recording
        try store.save(renamed)
        movingRecorder.writeDirectory = store.sessionURL(for: renamed)

        let stopped = try await manager.stopRecording()

        XCTAssertEqual(stopped.audioFilePaths.count, 1)
        let recoveredPath = try XCTUnwrap(stopped.audioFilePaths.first)
        XCTAssertTrue(FileManager.default.fileExists(atPath: recoveredPath), "Missing recovered file: \(recoveredPath)")
        XCTAssertTrue(recoveredPath.hasSuffix("microphone.m4a"))

        let micStatus = try XCTUnwrap(stopped.audioSourceStatuses.first { $0.source == .microphone })
        XCTAssertNotNil(micStatus.fileSizeBytes)
        XCTAssertNil(micStatus.missingReason)

        let loaded = try XCTUnwrap(store.load(id: started.id))
        XCTAssertEqual(loaded.audioFilePaths.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(loaded.audioFilePaths.first)))
    }

    func testStopRecordingClearsActiveSession() async throws {
        _ = try await manager.startRecording(title: "Meeting")
        _ = try await manager.stopRecording()
        XCTAssertNil(manager.activeSession)
    }

    func testStopWithNoActiveSessionThrows() async throws {
        do {
            _ = try await manager.stopRecording()
            XCTFail("Expected noActiveSession error")
        } catch RecordingManagerError.noActiveSession {
            // expected
        }
    }

    func testStopRecordingFailureSavesSessionAsFailed() async throws {
        _ = try await manager.startRecording(title: "Failing Stop")
        recorder.shouldFailOnStop = true
        do {
            _ = try await manager.stopRecording()
            XCTFail("Expected error")
        } catch {
            let sessions = try store.loadAll()
            XCTAssertEqual(sessions.count, 1)
            XCTAssertEqual(sessions.first?.status, .failed)
        }
    }

    // MARK: - Cancel

    func testCancelRecordingMarksSessionAsFailed() async throws {
        _ = try await manager.startRecording(title: "Cancelled")
        await manager.cancelRecording()
        let sessions = try store.loadAll()
        XCTAssertEqual(sessions.first?.status, .failed)
    }

    func testCancelWithNoActiveSessionIsNoop() async {
        await manager.cancelRecording()
        XCTAssertNil(manager.activeSession)
    }

    func testCancelClearsActiveSession() async throws {
        _ = try await manager.startRecording(title: "Cancel Me")
        await manager.cancelRecording()
        XCTAssertNil(manager.activeSession)
    }

    // MARK: - Interruption / Recovery

    func testInterruptedSessionsRecoveredOnStoreReload() async throws {
        _ = try await manager.startRecording(title: "Interrupted")
        // Simulate app restart by calling recoverInterruptedSessions
        try store.recoverInterruptedSessions()
        let sessions = try store.loadAll()
        XCTAssertEqual(sessions.first?.status, .failed)
    }

    // MARK: - End-to-End with MockAudioRecorder

    func testEndToEndRecordingCycle() async throws {
        XCTAssertFalse(manager.isRecording)

        let session = try await manager.startRecording(title: "E2E Test", date: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertTrue(manager.isRecording)
        XCTAssertEqual(session.status, .recording)

        let persisted = try store.load(id: session.id)
        XCTAssertEqual(persisted?.status, .recording)

        let stopped = try await manager.stopRecording()
        XCTAssertFalse(manager.isRecording)
        XCTAssertEqual(stopped.status, .stopped)
        XCTAssertEqual(stopped.audioFilePaths.count, 2)

        let final = try store.load(id: session.id)
        XCTAssertEqual(final?.status, .stopped)
        XCTAssertEqual(final?.audioFilePaths.count, 2)

        let micPath = stopped.audioFilePaths.first(where: { $0.hasSuffix("microphone.wav") })
        let sysPath = stopped.audioFilePaths.first(where: { $0.hasSuffix("system-audio.wav") })
        XCTAssertNotNil(micPath)
        XCTAssertNotNil(sysPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: micPath!))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sysPath!))
    }

    // MARK: - MockAudioRecorder unit tests

    func testMockRecorderStartsAndStops() async throws {
        XCTAssertFalse(recorder.isRecording)
        let dir = tempDir.appendingPathComponent("rec-test")
        try await recorder.startRecording(into: dir)
        XCTAssertTrue(recorder.isRecording)
        let urls = try await recorder.stopRecording()
        XCTAssertFalse(recorder.isRecording)
        XCTAssertEqual(urls.count, 2)
    }

    func testMockRecorderDoubleStartThrows() async throws {
        let dir = tempDir.appendingPathComponent("rec-double")
        try await recorder.startRecording(into: dir)
        do {
            try await recorder.startRecording(into: dir)
            XCTFail("Expected alreadyRecording")
        } catch AudioRecorderError.alreadyRecording {
            // expected
        }
    }

    func testMockRecorderStopWithoutStartThrows() async throws {
        do {
            _ = try await recorder.stopRecording()
            XCTFail("Expected notRecording")
        } catch AudioRecorderError.notRecording {
            // expected
        }
    }

    func testMockRecorderFailOnStart() async throws {
        recorder.shouldFailOnStart = true
        let dir = tempDir.appendingPathComponent("rec-fail-start")
        do {
            try await recorder.startRecording(into: dir)
            XCTFail("Expected recordingFailed")
        } catch AudioRecorderError.recordingFailed {
            XCTAssertFalse(recorder.isRecording)
        }
    }

    func testMockRecorderFailOnStop() async throws {
        let dir = tempDir.appendingPathComponent("rec-fail-stop")
        try await recorder.startRecording(into: dir)
        recorder.shouldFailOnStop = true
        do {
            _ = try await recorder.stopRecording()
            XCTFail("Expected recordingFailed")
        } catch AudioRecorderError.recordingFailed {
            XCTAssertFalse(recorder.isRecording)
        }
    }
}

private final class MovedFolderAudioRecorder: ConfigurableAudioRecorder, AudioCaptureReporter, @unchecked Sendable {
    private(set) var isRecording = false
    var writeDirectory: URL?
    var lastMissingReasons: [String: String] = [
        AudioSourceType.microphone.rawValue: "No samples received"
    ]

    func startRecording(into directory: URL) async throws {
        try await startRecording(into: directory, options: .default)
    }

    func startRecording(into directory: URL, options: AudioRecordingOptions) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        isRecording = true
    }

    func stopRecording() async throws -> [URL] {
        guard isRecording else { throw AudioRecorderError.notRecording }
        let directory = try XCTUnwrap(writeDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("microphone.m4a")
        try Data("audio data that exists despite a stale recorder URL".utf8).write(to: url)
        isRecording = false
        return []
    }
}

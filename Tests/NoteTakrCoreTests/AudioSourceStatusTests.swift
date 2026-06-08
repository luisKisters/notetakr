import XCTest
@testable import NoteTakrCore

final class AudioSourceStatusTests: XCTestCase {
    private var tempDir: URL!
    private var store: SessionStore!
    private var recorder: MockAudioRecorder!
    private var manager: RecordingManager!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioSourceStatusTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = SessionStore(baseURL: tempDir)
        recorder = MockAudioRecorder()
        manager = RecordingManager(store: store, recorder: recorder)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - AudioSourceStatus model

    func testAudioSourceStatusPresentDefaults() {
        let status = AudioSourceStatus(source: .microphone, fileSizeBytes: 1024)
        XCTAssertTrue(status.isPresent)
        XCTAssertNil(status.durationSeconds)
        XCTAssertNil(status.missingReason)
    }

    func testAudioSourceStatusMissingDefaults() {
        let status = AudioSourceStatus(source: .systemAudio)
        XCTAssertFalse(status.isPresent)
        XCTAssertNil(status.fileSizeBytes)
        XCTAssertNil(status.missingReason)
    }

    func testAudioSourceStatusMissingWithReason() {
        let status = AudioSourceStatus(
            source: .systemAudio,
            missingReason: "Screen Recording permission not granted"
        )
        XCTAssertFalse(status.isPresent)
        XCTAssertEqual(status.missingReason, "Screen Recording permission not granted")
    }

    func testAudioSourceStatusCodableRoundTrip() throws {
        let original = AudioSourceStatus(
            source: .microphone,
            fileSizeBytes: 204_800,
            durationSeconds: 65.5
        )
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(AudioSourceStatus.self, from: data)
        XCTAssertEqual(decoded.source, .microphone)
        XCTAssertEqual(decoded.fileSizeBytes, 204_800)
        let dur = try XCTUnwrap(decoded.durationSeconds)
        XCTAssertEqual(dur, 65.5, accuracy: 0.001)
        XCTAssertNil(decoded.missingReason)
    }

    func testAudioSourceStatusMissingCodableRoundTrip() throws {
        let original = AudioSourceStatus(
            source: .systemAudio,
            missingReason: "Capture start failure"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AudioSourceStatus.self, from: data)
        XCTAssertFalse(decoded.isPresent)
        XCTAssertEqual(decoded.missingReason, "Capture start failure")
    }

    func testAudioSourceTypeDisplayNames() {
        XCTAssertEqual(AudioSourceType.microphone.displayName, "Microphone")
        XCTAssertEqual(AudioSourceType.systemAudio.displayName, "System Audio")
    }

    func testAudioSourceTypeFileNamePrefixes() {
        XCTAssertEqual(AudioSourceType.microphone.fileNamePrefix, "microphone")
        XCTAssertEqual(AudioSourceType.systemAudio.fileNamePrefix, "system-audio")
    }

    // MARK: - deriveSourceStatuses

    func testDeriveSourceStatusesBothPresent() async throws {
        let dir = tempDir.appendingPathComponent("session-both")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let micURL = dir.appendingPathComponent("microphone.wav")
        let sysURL = dir.appendingPathComponent("system-audio.wav")
        let data = Data(repeating: 0, count: 512)
        try data.write(to: micURL)
        try data.write(to: sysURL)

        let statuses = RecordingManager.deriveSourceStatuses(
            returnedURLs: [micURL, sysURL],
            missingReasons: [:]
        )
        XCTAssertEqual(statuses.count, 2)
        let mic = statuses.first { $0.source == .microphone }
        let sys = statuses.first { $0.source == .systemAudio }
        XCTAssertNotNil(mic)
        XCTAssertNotNil(sys)
        XCTAssertTrue(mic!.isPresent)
        XCTAssertTrue(sys!.isPresent)
        XCTAssertEqual(mic!.fileSizeBytes, 512)
        XCTAssertEqual(sys!.fileSizeBytes, 512)
    }

    func testDeriveSourceStatusesMicOnlyPresent() async throws {
        let dir = tempDir.appendingPathComponent("session-mic-only")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let micURL = dir.appendingPathComponent("microphone.wav")
        try Data(repeating: 1, count: 256).write(to: micURL)

        let statuses = RecordingManager.deriveSourceStatuses(
            returnedURLs: [micURL],
            missingReasons: ["systemAudio": "Screen Recording permission not granted"]
        )
        let mic = statuses.first { $0.source == .microphone }
        let sys = statuses.first { $0.source == .systemAudio }
        XCTAssertTrue(mic!.isPresent)
        XCTAssertFalse(sys!.isPresent)
        XCTAssertEqual(sys!.missingReason, "Screen Recording permission not granted")
    }

    func testDeriveSourceStatusesMissingNoReason() {
        let statuses = RecordingManager.deriveSourceStatuses(
            returnedURLs: [],
            missingReasons: [:]
        )
        XCTAssertEqual(statuses.count, 2)
        for status in statuses {
            XCTAssertFalse(status.isPresent)
            XCTAssertNil(status.missingReason)
        }
    }

    // MARK: - RecordingManager integration

    func testStopRecordingPopulatesSourceStatusesBothPresent() async throws {
        _ = try await manager.startRecording(title: "Full Capture")
        let stopped = try await manager.stopRecording()
        XCTAssertEqual(stopped.audioSourceStatuses.count, 2)
        XCTAssertTrue(stopped.audioSourceStatuses.allSatisfy { $0.isPresent })
    }

    func testStopRecordingPopulatesSourceStatusesMicOnly() async throws {
        recorder.omitSystemAudio = true
        recorder.mockMissingReasons = ["systemAudio": "ScreenCaptureKit unavailable"]
        _ = try await manager.startRecording(title: "Mic Only")
        let stopped = try await manager.stopRecording()
        XCTAssertEqual(stopped.audioSourceStatuses.count, 2)
        let mic = stopped.audioSourceStatuses.first { $0.source == .microphone }
        let sys = stopped.audioSourceStatuses.first { $0.source == .systemAudio }
        XCTAssertTrue(mic!.isPresent)
        XCTAssertFalse(sys!.isPresent)
        XCTAssertEqual(sys!.missingReason, "ScreenCaptureKit unavailable")
    }

    func testStopRecordingPersistsSourceStatuses() async throws {
        recorder.omitSystemAudio = true
        let session = try await manager.startRecording(title: "Persisted Status")
        _ = try await manager.stopRecording()
        let loaded = try store.load(id: session.id)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded!.audioSourceStatuses.count, 2)
        let sys = loaded!.audioSourceStatuses.first { $0.source == .systemAudio }
        XCTAssertFalse(sys!.isPresent)
    }

    // MARK: - MeetingSession backward-compatible decode

    func testSessionDecodesWithoutAudioSourceStatuses() throws {
        // JSON matching the old schema (no audioSourceStatuses field).
        let json = """
        {
          "audioFilePaths": ["/tmp/mic.wav"],
          "date": "2024-01-01T00:00:00Z",
          "id": "12345678-1234-1234-1234-123456789012",
          "personalNotes": "",
          "status": "stopped",
          "title": "Legacy",
          "transcriptSegments": []
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let session = try decoder.decode(MeetingSession.self, from: json)
        XCTAssertEqual(session.title, "Legacy")
        XCTAssertTrue(session.audioSourceStatuses.isEmpty)
    }

    func testSessionDecodesWithAudioSourceStatuses() throws {
        let json = """
        {
          "audioFilePaths": ["/tmp/mic.wav"],
          "audioSourceStatuses": [
            {"source": "microphone", "fileSizeBytes": 1024},
            {"source": "systemAudio", "missingReason": "No permission"}
          ],
          "date": "2024-01-01T00:00:00Z",
          "id": "12345678-1234-1234-1234-123456789012",
          "personalNotes": "",
          "status": "stopped",
          "title": "New",
          "transcriptSegments": []
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let session = try decoder.decode(MeetingSession.self, from: json)
        XCTAssertEqual(session.audioSourceStatuses.count, 2)
        let mic = session.audioSourceStatuses.first { $0.source == .microphone }
        let sys = session.audioSourceStatuses.first { $0.source == .systemAudio }
        XCTAssertTrue(mic!.isPresent)
        XCTAssertFalse(sys!.isPresent)
        XCTAssertEqual(sys!.missingReason, "No permission")
    }
}

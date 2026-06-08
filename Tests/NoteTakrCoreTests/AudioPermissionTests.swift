import XCTest
@testable import NoteTakrCore

final class AudioPermissionTests: XCTestCase {

    func testPermissionStatusAllCases() {
        let all = PermissionStatus.allCases
        XCTAssertEqual(all.count, 3)
        XCTAssertTrue(all.contains(.notDetermined))
        XCTAssertTrue(all.contains(.granted))
        XCTAssertTrue(all.contains(.denied))
    }

    func testPermissionStatusRawValues() {
        XCTAssertEqual(PermissionStatus.notDetermined.rawValue, "notDetermined")
        XCTAssertEqual(PermissionStatus.granted.rawValue, "granted")
        XCTAssertEqual(PermissionStatus.denied.rawValue, "denied")
    }

    func testPermissionStatusEquality() {
        XCTAssertEqual(PermissionStatus.granted, PermissionStatus.granted)
        XCTAssertNotEqual(PermissionStatus.granted, PermissionStatus.denied)
        XCTAssertNotEqual(PermissionStatus.notDetermined, PermissionStatus.denied)
    }

    func testPermissionStatusIsSendable() {
        // Compile-time check: PermissionStatus conforms to Sendable.
        let status: PermissionStatus = .granted
        let box: any Sendable = status
        _ = box
    }

    func testPermissionStatusRoundTrip() {
        for status in PermissionStatus.allCases {
            let raw = status.rawValue
            let recovered = PermissionStatus(rawValue: raw)
            XCTAssertEqual(recovered, status)
        }
    }

    // MARK: - Mock-driven permission behavior

    func testGrantedPermissionAllowsRecording() async throws {
        // Simulates the scenario where both permissions are granted before recording starts.
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PermissionTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = SessionStore(baseURL: tempDir)
        let recorder = MockAudioRecorder()
        let manager = RecordingManager(store: store, recorder: recorder)

        // Start a recording — this should succeed regardless of OS-level permissions
        // because the mock recorder doesn't require real microphone access.
        let session = try await manager.startRecording(title: "Permission Test")
        XCTAssertEqual(session.status, .recording)

        let stopped = try await manager.stopRecording()
        XCTAssertEqual(stopped.status, .stopped)
        XCTAssertEqual(stopped.audioFilePaths.count, 2)
    }

    func testDeniedPermissionSimulatedByRecorderFailure() async throws {
        // Simulates what happens when the audio recorder fails due to denied permissions.
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PermissionTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = SessionStore(baseURL: tempDir)
        let recorder = MockAudioRecorder()
        recorder.shouldFailOnStart = true
        let manager = RecordingManager(store: store, recorder: recorder)

        do {
            _ = try await manager.startRecording(title: "Denied Recording")
            XCTFail("Expected recording failure when permission is denied")
        } catch AudioRecorderError.recordingFailed {
            let sessions = try store.loadAll()
            XCTAssertEqual(sessions.first?.status, .failed)
        }
    }
}

import XCTest
import AVFoundation
import NoteTakrCore
@testable import NoteTakr

final class NativeAudioRecorderTests: XCTestCase {

    func testNativeAudioRecorderConformsToProtocol() {
        // Compile-time check: NativeAudioRecorder satisfies the AudioRecorder protocol.
        let recorder: any AudioRecorder = NativeAudioRecorder()
        XCTAssertFalse(recorder.isRecording)
    }

    func testNativeAudioRecorderInstantiates() {
        let recorder = NativeAudioRecorder()
        XCTAssertNotNil(recorder)
        XCTAssertFalse(recorder.isRecording)
    }

    func testSystemAudioCapturerInstantiates() {
        // Compile-time check: SystemAudioCapturer can be instantiated.
        let capturer = SystemAudioCapturer()
        XCTAssertNotNil(capturer)
    }

    @MainActor
    func testAudioPermissionManagerInstantiates() {
        // Compile-time check: AudioPermissionManager can be created on the main actor.
        let manager = AudioPermissionManager()
        XCTAssertNotNil(manager)
        // microphoneStatus is either .notDetermined, .granted, or .denied depending on environment.
        XCTAssertTrue(PermissionStatus.allCases.contains(manager.microphoneStatus))
        XCTAssertTrue(PermissionStatus.allCases.contains(manager.systemAudioStatus))
        XCTAssertFalse(manager.systemAudioRestartRequired)
    }
}

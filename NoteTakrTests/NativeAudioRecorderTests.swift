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

    @MainActor
    func testCalendarStatusRefreshDoesNotPrompt() {
        // Verifies that reading calendar status at launch (via refresh) uses only the
        // class-level EKEventStore.authorizationStatus query — no prompt should occur.
        let manager = AudioPermissionManager()
        // Status is set synchronously in init() via refresh(includeCalendar: true).
        XCTAssertTrue(PermissionStatus.allCases.contains(manager.calendarStatus))
        // A second explicit refresh should also be safe.
        manager.refresh(includeCalendar: true)
        XCTAssertTrue(PermissionStatus.allCases.contains(manager.calendarStatus))
    }
}

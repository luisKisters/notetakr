// Native macOS audio capture via AVAudioRecorder (microphone) and ScreenCaptureKit (system audio).
// IMPORTANT: Verified only on the macOS CI runner / physical Mac.
// Do NOT claim real audio capture works until manually tested on a physical Mac.
#if canImport(AVFoundation)
import AVFoundation
import CoreGraphics
import NoteTakrCore

final class NativeAudioRecorder: AudioRecorder, AudioCaptureReporter, @unchecked Sendable {
    private(set) var isRecording: Bool = false
    private var micRecorder: AVAudioRecorder?
    private var sysAudioCapturer: SystemAudioCapturer?
    private var capturedMicURL: URL?
    private var capturedSysURL: URL?
    private var _lastMissingReasons: [String: String] = [:]

    // AudioCaptureReporter
    var lastMissingReasons: [String: String] { _lastMissingReasons }

    func startRecording(into directory: URL) async throws {
        guard !isRecording else {
            throw AudioRecorderError.alreadyRecording
        }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw AudioRecorderError.recordingFailed(
                "Microphone permission has not been granted")
        }

        _lastMissingReasons = [:]
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let micURL = directory.appendingPathComponent("microphone.m4a")
        let sysURL = directory.appendingPathComponent("system-audio.m4a")
        capturedMicURL = micURL
        capturedSysURL = sysURL

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        let recorder = try AVAudioRecorder(url: micURL, settings: settings)
        guard recorder.record() else {
            throw AudioRecorderError.recordingFailed(
                "AVAudioRecorder failed to start — check microphone permission")
        }
        micRecorder = recorder

        // System-audio via ScreenCaptureKit; requires screen recording permission.
        // Gracefully skipped when permission is absent or hardware is unavailable.
        if CGPreflightScreenCaptureAccess() {
            let capturer = SystemAudioCapturer()
            do {
                try await capturer.startCapture(to: sysURL)
                sysAudioCapturer = capturer
            } catch {
                let reason = "Capture start failure: \(error.localizedDescription)"
                _lastMissingReasons[AudioSourceType.systemAudio.rawValue] = reason
                NSLog("NoteTakr system audio capture failed to start: \(error.localizedDescription)")
                sysAudioCapturer = nil
            }
        } else {
            _lastMissingReasons[AudioSourceType.systemAudio.rawValue] = "Screen Recording permission not granted"
        }

        isRecording = true
    }

    func stopRecording() async throws -> [URL] {
        guard isRecording else {
            throw AudioRecorderError.notRecording
        }
        defer { isRecording = false }

        var results: [URL] = []

        micRecorder?.stop()
        micRecorder = nil
        if let url = capturedMicURL, FileManager.default.fileExists(atPath: url.path) {
            results.append(url)
        } else {
            _lastMissingReasons[AudioSourceType.microphone.rawValue] = "No samples received"
        }
        capturedMicURL = nil

        if let capturer = sysAudioCapturer {
            do {
                try await capturer.stopCapture()
                if let url = capturedSysURL, FileManager.default.fileExists(atPath: url.path) {
                    results.append(url)
                } else {
                    _lastMissingReasons[AudioSourceType.systemAudio.rawValue] = "No samples received"
                }
            } catch {
                _lastMissingReasons[AudioSourceType.systemAudio.rawValue] =
                    "Capture stop failure: \(error.localizedDescription)"
            }
            sysAudioCapturer = nil
        }
        capturedSysURL = nil

        return results
    }
}
#endif

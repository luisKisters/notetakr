// Native macOS audio capture via AVAudioRecorder (microphone) and ScreenCaptureKit (system audio).
// IMPORTANT: Verified only on the macOS CI runner / physical Mac.
// Do NOT claim real audio capture works until manually tested on a physical Mac.
#if canImport(AVFoundation)
import AVFoundation
import CoreGraphics
import NoteTakrCore

final class NativeAudioRecorder: ConfigurableAudioRecorder, AudioCaptureReporter, @unchecked Sendable {
    private(set) var isRecording: Bool = false
    private var micRecorder: AVAudioRecorder?
    private var sysAudioCapturer: SystemAudioCapturer?
    private var capturedMicURL: URL?
    private var capturedSysURL: URL?
    private var currentOptions: AudioRecordingOptions = .default
    private var _lastMissingReasons: [String: String] = [:]

    // AudioCaptureReporter
    var lastMissingReasons: [String: String] { _lastMissingReasons }

    func startRecording(into directory: URL) async throws {
        try await startRecording(into: directory, options: .default)
    }

    func startRecording(into directory: URL, options: AudioRecordingOptions) async throws {
        guard !isRecording else {
            throw AudioRecorderError.alreadyRecording
        }
        guard options.microphoneEnabled || options.systemAudioEnabled else {
            throw AudioRecorderError.recordingFailed("No audio sources are enabled")
        }
        if options.microphoneEnabled, AVCaptureDevice.authorizationStatus(for: .audio) != .authorized {
            throw AudioRecorderError.recordingFailed(
                "Microphone permission has not been granted")
        }

        _lastMissingReasons = [:]
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let micURL = directory.appendingPathComponent("microphone.m4a")
        let sysURL = directory.appendingPathComponent("system-audio.m4a")
        capturedMicURL = options.microphoneEnabled ? micURL : nil
        capturedSysURL = options.systemAudioEnabled ? sysURL : nil
        currentOptions = options

        if options.microphoneEnabled {
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
        } else {
            _lastMissingReasons[AudioSourceType.microphone.rawValue] = "Microphone disabled"
        }

        // System-audio via ScreenCaptureKit; requires screen recording permission.
        // Gracefully skipped when permission is absent or hardware is unavailable.
        if !options.systemAudioEnabled {
            _lastMissingReasons[AudioSourceType.systemAudio.rawValue] = "System audio disabled"
        } else if CGPreflightScreenCaptureAccess() {
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

        guard micRecorder != nil || sysAudioCapturer != nil else {
            currentOptions = .default
            capturedMicURL = nil
            capturedSysURL = nil
            let reason = _lastMissingReasons.values.sorted().joined(separator: "; ")
            throw AudioRecorderError.recordingFailed(reason.isEmpty ? "No audio sources started" : reason)
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
        } else if currentOptions.microphoneEnabled {
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
        currentOptions = .default

        return results
    }
}
#endif

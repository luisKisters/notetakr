// Native macOS audio capture via AVAudioRecorder (microphone) and ScreenCaptureKit (system audio).
// IMPORTANT: Verified only on the macOS CI runner / physical Mac.
// Do NOT claim real audio capture works until manually tested on a physical Mac.
#if canImport(AVFoundation)
import AVFoundation
import NoteTakrCore

final class NativeAudioRecorder: AudioRecorder, @unchecked Sendable {
    private(set) var isRecording: Bool = false
    private var micRecorder: AVAudioRecorder?
    private var sysAudioCapturer: SystemAudioCapturer?
    private var capturedMicURL: URL?
    private var capturedSysURL: URL?

    func startRecording(into directory: URL) async throws {
        guard !isRecording else {
            throw AudioRecorderError.alreadyRecording
        }
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
        let capturer = SystemAudioCapturer()
        do {
            try await capturer.startCapture(to: sysURL)
            sysAudioCapturer = capturer
        } catch {
            sysAudioCapturer = nil
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
        }
        capturedMicURL = nil

        if let capturer = sysAudioCapturer {
            do {
                try await capturer.stopCapture()
                if let url = capturedSysURL, FileManager.default.fileExists(atPath: url.path) {
                    results.append(url)
                }
            } catch {
                // System-audio stop failed; continue with microphone recording only.
            }
            sysAudioCapturer = nil
        }
        capturedSysURL = nil

        return results
    }
}
#endif

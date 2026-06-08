// Native macOS audio capture — implemented in Task 4.
// Verified only on the macOS CI runner / physical Mac.
#if canImport(AVFoundation)
import AVFoundation
import NoteTakrCore

final class NativeAudioRecorder: AudioRecorder, @unchecked Sendable {
    private(set) var isRecording: Bool = false

    func startRecording(into directory: URL) async throws {
        // Real AVAudioRecorder wiring added in Task 4.
        isRecording = true
    }

    func stopRecording() async throws -> [URL] {
        isRecording = false
        return []
    }
}
#endif

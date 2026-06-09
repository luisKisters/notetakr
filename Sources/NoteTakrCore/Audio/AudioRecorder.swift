import Foundation

public enum AudioRecorderError: Error, Sendable, Equatable {
    case alreadyRecording
    case notRecording
    case recordingFailed(String)
}

public protocol AudioRecorder: AnyObject, Sendable {
    var isRecording: Bool { get }
    func startRecording(into directory: URL) async throws
    /// Starts recording, honouring the meeting mode (e.g. an in-person meeting
    /// skips system-audio capture and records the microphone only).
    func startRecording(into directory: URL, mode: MeetingMode) async throws
    func stopRecording() async throws -> [URL]
}

public extension AudioRecorder {
    /// Recorders that don't care about the mode fall back to the plain start.
    func startRecording(into directory: URL, mode: MeetingMode) async throws {
        try await startRecording(into: directory)
    }
}

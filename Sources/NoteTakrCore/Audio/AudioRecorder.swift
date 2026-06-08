import Foundation

public enum AudioRecorderError: Error, Sendable, Equatable {
    case alreadyRecording
    case notRecording
    case recordingFailed(String)
}

public protocol AudioRecorder: AnyObject, Sendable {
    var isRecording: Bool { get }
    func startRecording(into directory: URL) async throws
    func stopRecording() async throws -> [URL]
}

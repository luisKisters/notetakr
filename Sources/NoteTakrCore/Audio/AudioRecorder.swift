import Foundation

public enum AudioRecorderError: Error, Sendable, Equatable {
    case alreadyRecording
    case notRecording
    case recordingFailed(String)
}

public struct AudioRecordingOptions: Codable, Equatable, Sendable {
    public var microphoneEnabled: Bool
    public var systemAudioEnabled: Bool

    public init(microphoneEnabled: Bool = true, systemAudioEnabled: Bool = true) {
        self.microphoneEnabled = microphoneEnabled
        self.systemAudioEnabled = systemAudioEnabled
    }

    public static let `default` = AudioRecordingOptions()
}

public protocol AudioRecorder: AnyObject, Sendable {
    var isRecording: Bool { get }
    func startRecording(into directory: URL) async throws
    func stopRecording() async throws -> [URL]
}

public protocol ConfigurableAudioRecorder: AudioRecorder {
    func startRecording(into directory: URL, options: AudioRecordingOptions) async throws
}

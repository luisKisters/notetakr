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

/// A recorder whose active capture sources can be changed without ending the
/// meeting. NoteTakr uses this when an online meeting becomes in-person while
/// recording, so desktop audio stops immediately while the microphone keeps running.
public protocol ReconfigurableAudioRecorder: ConfigurableAudioRecorder {
    func updateRecording(options: AudioRecordingOptions) async throws
}

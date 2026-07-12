import Foundation

public enum PermissionStatus: String, Sendable, Equatable, CaseIterable {
    case notDetermined
    case granted
    case denied
}

/// The permission decision for an attempted recording. Only enabled sources are
/// required: an in-person (microphone-only) recording never needs screen capture.
public enum AudioRecordingPermissionFailure: Sendable, Equatable {
    case microphone
    case systemAudio
}

public enum AudioRecordingPermissionGate {
    public static func failure(
        for options: AudioRecordingOptions,
        microphoneStatus: PermissionStatus,
        systemAudioStatus: PermissionStatus
    ) -> AudioRecordingPermissionFailure? {
        if options.microphoneEnabled, microphoneStatus != .granted {
            return .microphone
        }
        if options.systemAudioEnabled, systemAudioStatus != .granted {
            return .systemAudio
        }
        return nil
    }
}

import Foundation

public enum AudioSourceType: String, Codable, Equatable, Sendable, CaseIterable {
    case microphone
    case systemAudio

    public var displayName: String {
        switch self {
        case .microphone: return "Microphone"
        case .systemAudio: return "System Audio"
        }
    }

    // Prefix used for the output file name (without extension).
    public var fileNamePrefix: String {
        switch self {
        case .microphone: return "microphone"
        case .systemAudio: return "system-audio"
        }
    }
}

public struct AudioSourceStatus: Codable, Identifiable, Equatable, Sendable {
    public var source: AudioSourceType
    public var fileSizeBytes: Int64?
    public var durationSeconds: Double?
    public var missingReason: String?

    public var id: AudioSourceType { source }
    public var isPresent: Bool { (fileSizeBytes ?? 0) > 0 }

    public init(
        source: AudioSourceType,
        fileSizeBytes: Int64? = nil,
        durationSeconds: Double? = nil,
        missingReason: String? = nil
    ) {
        self.source = source
        self.fileSizeBytes = fileSizeBytes
        self.durationSeconds = durationSeconds
        self.missingReason = missingReason
    }
}

// Implement manually so Identifiable's `id` computed property is excluded from Codable.
extension AudioSourceStatus {
    enum CodingKeys: String, CodingKey {
        case source, fileSizeBytes, durationSeconds, missingReason
    }
}

// AudioCaptureReporter allows recorders to expose why an audio source was not captured.
// Conformance is optional; RecordingManager checks for it at runtime via `as?`.
public protocol AudioCaptureReporter: AnyObject {
    // Keys are AudioSourceType.rawValue; values are human-readable reason strings.
    var lastMissingReasons: [String: String] { get }
}

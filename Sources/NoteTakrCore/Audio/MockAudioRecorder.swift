import Foundation

public final class MockAudioRecorder: ReconfigurableAudioRecorder, AudioCaptureReporter, @unchecked Sendable {
    public private(set) var isRecording: Bool = false
    private var currentDirectory: URL?
    private var currentOptions: AudioRecordingOptions = .default

    public var shouldFailOnStart: Bool = false
    public var shouldFailOnStop: Bool = false
    public var mockMissingReasons: [String: String] = [:]
    public private(set) var startCallCount: Int = 0
    public private(set) var stopCallCount: Int = 0
    public private(set) var lastStartOptions: AudioRecordingOptions?
    public private(set) var lastUpdateOptions: AudioRecordingOptions?

    // AudioCaptureReporter
    public var lastMissingReasons: [String: String] { mockMissingReasons }

    // Controls whether system-audio.wav is omitted from stopRecording results.
    public var omitSystemAudio: Bool = false

    public init() {}

    public func startRecording(into directory: URL) async throws {
        try await startRecording(into: directory, options: .default)
    }

    public func startRecording(into directory: URL, options: AudioRecordingOptions) async throws {
        startCallCount += 1
        lastStartOptions = options
        if shouldFailOnStart {
            throw AudioRecorderError.recordingFailed("mock start failure")
        }
        guard !isRecording else {
            throw AudioRecorderError.alreadyRecording
        }
        guard options.microphoneEnabled || options.systemAudioEnabled else {
            throw AudioRecorderError.recordingFailed("No audio sources are enabled")
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        currentDirectory = directory
        currentOptions = options
        if !options.microphoneEnabled {
            mockMissingReasons[AudioSourceType.microphone.rawValue] = "Microphone disabled"
        }
        if !options.systemAudioEnabled {
            mockMissingReasons[AudioSourceType.systemAudio.rawValue] = "System audio disabled"
        }
        isRecording = true
    }

    public func stopRecording() async throws -> [URL] {
        stopCallCount += 1
        guard isRecording, let dir = currentDirectory else {
            throw AudioRecorderError.notRecording
        }
        if shouldFailOnStop {
            isRecording = false
            currentDirectory = nil
            throw AudioRecorderError.recordingFailed("mock stop failure")
        }
        let placeholder = Data("RIFF fixture".utf8)
        var results: [URL] = []
        if currentOptions.microphoneEnabled {
            let micURL = dir.appendingPathComponent("microphone.wav")
            try placeholder.write(to: micURL)
            results.append(micURL)
        }
        if currentOptions.systemAudioEnabled && !omitSystemAudio {
            let sysURL = dir.appendingPathComponent("system-audio.wav")
            try placeholder.write(to: sysURL)
            results.append(sysURL)
        }
        isRecording = false
        currentDirectory = nil
        currentOptions = .default
        return results
    }

    public func updateRecording(options: AudioRecordingOptions) async throws {
        guard isRecording else { throw AudioRecorderError.notRecording }
        guard options.microphoneEnabled || options.systemAudioEnabled else {
            throw AudioRecorderError.recordingFailed("No audio sources are enabled")
        }
        currentOptions = options
        lastUpdateOptions = options
        if options.microphoneEnabled {
            mockMissingReasons.removeValue(forKey: AudioSourceType.microphone.rawValue)
        } else {
            mockMissingReasons[AudioSourceType.microphone.rawValue] = "Microphone disabled"
        }
        if options.systemAudioEnabled {
            mockMissingReasons.removeValue(forKey: AudioSourceType.systemAudio.rawValue)
        } else {
            mockMissingReasons[AudioSourceType.systemAudio.rawValue] = "System audio disabled"
        }
    }
}

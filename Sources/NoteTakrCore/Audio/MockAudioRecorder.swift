import Foundation

public final class MockAudioRecorder: AudioRecorder, AudioCaptureReporter, @unchecked Sendable {
    public private(set) var isRecording: Bool = false
    private var currentDirectory: URL?

    public var shouldFailOnStart: Bool = false
    public var shouldFailOnStop: Bool = false
    public var mockMissingReasons: [String: String] = [:]
    public private(set) var startCallCount: Int = 0
    public private(set) var stopCallCount: Int = 0

    // AudioCaptureReporter
    public var lastMissingReasons: [String: String] { mockMissingReasons }

    // Controls whether system-audio.wav is omitted from stopRecording results.
    public var omitSystemAudio: Bool = false

    // The mode passed to the most recent startRecording call.
    public private(set) var lastMode: MeetingMode?

    public init() {}

    public func startRecording(into directory: URL) async throws {
        try await startRecording(into: directory, mode: .online)
    }

    public func startRecording(into directory: URL, mode: MeetingMode) async throws {
        startCallCount += 1
        lastMode = mode
        if shouldFailOnStart {
            throw AudioRecorderError.recordingFailed("mock start failure")
        }
        guard !isRecording else {
            throw AudioRecorderError.alreadyRecording
        }
        // In person: microphone only, no system audio captured.
        if !mode.capturesSystemAudio {
            omitSystemAudio = true
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        currentDirectory = directory
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
        let micURL = dir.appendingPathComponent("microphone.wav")
        let sysURL = dir.appendingPathComponent("system-audio.wav")
        let placeholder = Data("RIFF fixture".utf8)
        try placeholder.write(to: micURL)
        var results: [URL] = [micURL]
        if !omitSystemAudio {
            try placeholder.write(to: sysURL)
            results.append(sysURL)
        }
        isRecording = false
        currentDirectory = nil
        return results
    }
}

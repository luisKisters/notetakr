import Foundation

public final class MockAudioRecorder: AudioRecorder, @unchecked Sendable {
    public private(set) var isRecording: Bool = false
    private var currentDirectory: URL?

    public var shouldFailOnStart: Bool = false
    public var shouldFailOnStop: Bool = false
    public private(set) var startCallCount: Int = 0
    public private(set) var stopCallCount: Int = 0

    public init() {}

    public func startRecording(into directory: URL) async throws {
        startCallCount += 1
        if shouldFailOnStart {
            throw AudioRecorderError.recordingFailed("mock start failure")
        }
        guard !isRecording else {
            throw AudioRecorderError.alreadyRecording
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
        try placeholder.write(to: sysURL)
        isRecording = false
        currentDirectory = nil
        return [micURL, sysURL]
    }
}

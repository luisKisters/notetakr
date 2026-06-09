import XCTest
import NoteTakrCore
@testable import NoteTakr

final class FluidAudioAdapterTests: XCTestCase {

    func testConformsToTranscriptionEngine() {
        let store = TranscriptionSettingsStore(fileURL: makeTempFileURL())
        let adapter: any TranscriptionEngine = FluidAudioAdapter(settingsStore: store, runtime: FakeFluidAudioRuntime())
        XCTAssertNotNil(adapter)
    }

    func testNotConfiguredThrowsModelUnavailable() async throws {
        let store = TranscriptionSettingsStore(fileURL: makeTempFileURL())
        try store.save(.default)
        let runtime = FakeFluidAudioRuntime()
        let adapter = FluidAudioAdapter(settingsStore: store, runtime: runtime)

        do {
            _ = try await adapter.transcribe(audioURL: makeAudioURL(), vocabulary: [])
            XCTFail("Expected modelUnavailable")
        } catch TranscriptionError.modelUnavailable {
            XCTAssertNil(runtime.receivedSettings)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSelectedFolderSettingsPassedToRuntime() async throws {
        let settings = TranscriptionModelSettings(
            source: .localFolder(URL(fileURLWithPath: "/tmp/parakeet-tdt-0.6b-v3-coreml", isDirectory: true)),
            modelVersion: .v3
        )
        let store = TranscriptionSettingsStore(fileURL: makeTempFileURL())
        try store.save(settings)
        let runtime = FakeFluidAudioRuntime(text: "Selected folder transcript")
        let adapter = FluidAudioAdapter(settingsStore: store, runtime: runtime)

        let segments = try await adapter.transcribe(audioURL: makeAudioURL(), vocabulary: [])

        XCTAssertEqual(runtime.receivedSettings, settings)
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].timestamp, 0)
        XCTAssertNil(segments[0].speaker)
        XCTAssertEqual(segments[0].text, "Selected folder transcript")
    }

    func testAutomaticDownloadSettingsPassedToRuntime() async throws {
        let settings = TranscriptionModelSettings(
            source: .fluidAudioDefaultCache,
            modelVersion: .tdtCtc110m
        )
        let store = TranscriptionSettingsStore(fileURL: makeTempFileURL())
        try store.save(settings)
        let runtime = FakeFluidAudioRuntime(text: "Automatic transcript")
        let adapter = FluidAudioAdapter(settingsStore: store, runtime: runtime)

        let segments = try await adapter.transcribe(audioURL: makeAudioURL(), vocabulary: [
            VocabularyEntry(phrase: "NoteTakr", isEnabled: true, boostingWeight: 1.5),
        ])

        XCTAssertEqual(runtime.receivedSettings, settings)
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].timestamp, 0)
        XCTAssertNil(segments[0].speaker)
        XCTAssertEqual(segments[0].text, "Automatic transcript")
    }

    func testRuntimeFailurePropagates() async throws {
        let store = TranscriptionSettingsStore(fileURL: makeTempFileURL())
        try store.save(TranscriptionModelSettings(source: .fluidAudioDefaultCache, modelVersion: .v2))
        let runtime = FakeFluidAudioRuntime(error: TranscriptionError.transcriptionFailed("boom"))
        let adapter = FluidAudioAdapter(settingsStore: store, runtime: runtime)

        do {
            _ = try await adapter.transcribe(audioURL: makeAudioURL(), vocabulary: [])
            XCTFail("Expected transcriptionFailed")
        } catch TranscriptionError.transcriptionFailed(let message) {
            XCTAssertEqual(message, "boom")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func makeTempFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("FluidAudioAdapterTests-\(UUID().uuidString)")
            .appendingPathComponent("transcription-settings.json")
    }

    private func makeAudioURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("audio-\(UUID().uuidString).wav")
    }
}

final class FakeFluidAudioRuntime: FluidAudioRuntimeProtocol, @unchecked Sendable {
    private let text: String
    private let error: Error?
    private(set) var receivedAudioURL: URL?
    private(set) var receivedSettings: TranscriptionModelSettings?

    init(text: String = "Transcript text", error: Error? = nil) {
        self.text = text
        self.error = error
    }

    func transcribe(audioURL: URL, settings: TranscriptionModelSettings) async throws -> String {
        receivedAudioURL = audioURL
        receivedSettings = settings
        if let error {
            throw error
        }
        return text
    }
}

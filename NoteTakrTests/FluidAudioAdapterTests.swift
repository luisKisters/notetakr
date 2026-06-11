import XCTest
import FluidAudio
import NoteTakrCore
import NoteTakrKit
@testable import NoteTakr

final class FluidAudioAdapterTests: XCTestCase {

    func testConformsToTranscriptionEngine() {
        let store = TranscriptionSettingsStore(fileURL: makeTempFileURL())
        let adapter: any TranscriptionEngine = makeAdapter(store: store, runtime: FakeFluidAudioRuntime())
        XCTAssertNotNil(adapter)
    }

    func testNotConfiguredThrowsModelUnavailable() async throws {
        let store = TranscriptionSettingsStore(fileURL: makeTempFileURL())
        try store.save(.default)
        let runtime = FakeFluidAudioRuntime()
        let loader = FakeAudioLoader()
        let adapter = makeAdapter(store: store, runtime: runtime, loader: loader)

        do {
            _ = try await adapter.transcribe(audioURL: makeAudioURL(), vocabulary: [])
            XCTFail("Expected modelUnavailable")
        } catch TranscriptionError.modelUnavailable {
            XCTAssertNil(runtime.receivedSettings, "Runtime should not be called when not configured")
            XCTAssertFalse(loader.didLoad, "Audio should not be decoded when not configured")
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
        let adapter = makeAdapter(store: store, runtime: runtime)

        let segments = try await adapter.transcribe(audioURL: makeAudioURL(), vocabulary: [])

        XCTAssertEqual(runtime.receivedSettings, settings)
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].timestamp, 0)
        XCTAssertNil(segments[0].speaker)
        XCTAssertEqual(segments[0].text, "Selected folder transcript")
    }

    func testDiarizationProducesSpeakerLabelledSegments() async throws {
        let store = TranscriptionSettingsStore(fileURL: makeTempFileURL())
        try store.save(TranscriptionModelSettings(source: .fluidAudioDefaultCache, modelVersion: .v3))
        let timings = [
            token("\u{2581}Hello", 0.0, 0.5),
            token("\u{2581}there", 0.5, 1.0),
            token("\u{2581}Hi", 2.0, 2.5),
        ]
        let runtime = FakeFluidAudioRuntime(text: "Hello there Hi", tokenTimings: timings)
        let diarizer = FakeDiarizer(spans: [
            SpeakerSpan(speakerId: "A", start: 0.0, end: 1.5),
            SpeakerSpan(speakerId: "B", start: 1.5, end: 3.0),
        ])
        let adapter = makeAdapter(store: store, runtime: runtime, diarizer: diarizer)

        let segments = try await adapter.transcribe(audioURL: makeAudioURL(), vocabulary: [])

        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].speaker, "Speaker 1")
        XCTAssertEqual(segments[0].text, "Hello there")
        XCTAssertEqual(segments[1].speaker, "Speaker 2")
        XCTAssertEqual(segments[1].text, "Hi")
    }

    func testMultiSourceCollapsesMicAndOffsetsSystemSpeakers() async throws {
        let store = TranscriptionSettingsStore(fileURL: makeTempFileURL())
        try store.save(TranscriptionModelSettings(source: .fluidAudioDefaultCache, modelVersion: .v3))
        let timings = [
            token("\u{2581}Hello", 0.0, 0.5),
            token("\u{2581}there", 0.5, 1.0),
        ]
        let runtime = FakeFluidAudioRuntime(text: "Hello there", tokenTimings: timings)
        let diarizer = FakeDiarizer(spans: [SpeakerSpan(speakerId: "A", start: 0.0, end: 1.0)])
        let adapter = makeAdapter(store: store, runtime: runtime, diarizer: diarizer)

        let mic = TranscriptionSource(url: makeAudioURL(), role: .microphone)
        let system = TranscriptionSource(url: makeAudioURL(), role: .systemAudio)
        let segments = try await adapter.transcribe(sources: [mic, system], vocabulary: [])

        let speakers = Set(segments.compactMap(\.speaker))
        // Microphone collapses to "Speaker 1 (You)"; the system stream's diarized
        // speaker is shifted to "Speaker 2".
        XCTAssertTrue(speakers.contains("Speaker 1 (You)"), "Expected mic label, got \(speakers)")
        XCTAssertTrue(speakers.contains("Speaker 2"), "Expected offset system label, got \(speakers)")
    }

    func testSingleSourceFallsBackToLegacyDiarization() async throws {
        let store = TranscriptionSettingsStore(fileURL: makeTempFileURL())
        try store.save(TranscriptionModelSettings(source: .fluidAudioDefaultCache, modelVersion: .v3))
        let timings = [token("\u{2581}Hello", 0.0, 0.5)]
        let runtime = FakeFluidAudioRuntime(text: "Hello", tokenTimings: timings)
        let diarizer = FakeDiarizer(spans: [SpeakerSpan(speakerId: "A", start: 0.0, end: 1.0)])
        let adapter = makeAdapter(store: store, runtime: runtime, diarizer: diarizer)

        let only = TranscriptionSource(url: makeAudioURL(), role: .systemAudio)
        let segments = try await adapter.transcribe(sources: [only], vocabulary: [])

        // A lone source keeps the legacy "Speaker 1/2…" labelling (not offset).
        XCTAssertEqual(segments.first?.speaker, "Speaker 1")
    }

    func testRuntimeFailurePropagates() async throws {
        let store = TranscriptionSettingsStore(fileURL: makeTempFileURL())
        try store.save(TranscriptionModelSettings(source: .fluidAudioDefaultCache, modelVersion: .v2))
        let runtime = FakeFluidAudioRuntime(error: TranscriptionError.transcriptionFailed("boom"))
        let adapter = makeAdapter(store: store, runtime: runtime)

        do {
            _ = try await adapter.transcribe(audioURL: makeAudioURL(), vocabulary: [])
            XCTFail("Expected transcriptionFailed")
        } catch TranscriptionError.transcriptionFailed(let message) {
            XCTAssertEqual(message, "boom")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Helpers

    private func makeAdapter(
        store: TranscriptionSettingsStore,
        runtime: FakeFluidAudioRuntime,
        loader: FakeAudioLoader = FakeAudioLoader(),
        diarizer: FakeDiarizer = FakeDiarizer(spans: [])
    ) -> FluidAudioAdapter {
        FluidAudioAdapter(
            settingsStore: store,
            runtime: runtime,
            audioLoader: loader,
            diarizer: diarizer,
            booster: NoopVocabularyBooster()
        )
    }

    private func token(_ text: String, _ start: TimeInterval, _ end: TimeInterval) -> TokenTiming {
        TokenTiming(token: text, tokenId: 0, startTime: start, endTime: end, confidence: 1.0)
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
    private let tokenTimings: [TokenTiming]?
    private let error: Error?
    private(set) var receivedSettings: TranscriptionModelSettings?

    init(text: String = "Transcript text", tokenTimings: [TokenTiming]? = nil, error: Error? = nil) {
        self.text = text
        self.tokenTimings = tokenTimings
        self.error = error
    }

    func transcribe(samples: [Float], settings: TranscriptionModelSettings) async throws -> ASRResult {
        receivedSettings = settings
        if let error { throw error }
        return ASRResult(
            text: text, confidence: 1.0, duration: 1.0, processingTime: 0.1, tokenTimings: tokenTimings
        )
    }
}

final class FakeAudioLoader: AudioSampleLoading, @unchecked Sendable {
    private(set) var didLoad = false
    func loadSamples(from url: URL) throws -> [Float] {
        didLoad = true
        return []
    }
}

final class FakeDiarizer: SpeakerDiarizing, @unchecked Sendable {
    private let spans: [SpeakerSpan]
    init(spans: [SpeakerSpan]) { self.spans = spans }
    func diarize(samples: [Float]) async throws -> [SpeakerSpan] { spans }
}

final class NoopVocabularyBooster: VocabularyBoosting, @unchecked Sendable {
    func boost(
        samples: [Float],
        transcript: String,
        tokenTimings: [TokenTiming],
        entries: [VocabularyEntry]
    ) async throws -> [WordReplacement] {
        []
    }
}

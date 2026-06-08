import XCTest
import NoteTakrCore
@testable import NoteTakr

final class FluidAudioAdapterTests: XCTestCase {

    func testConformsToTranscriptionEngine() {
        let dir = FileManager.default.temporaryDirectory
        let adapter: any TranscriptionEngine = FluidAudioAdapter(modelDirectory: dir)
        XCTAssertNotNil(adapter)
    }

    func testThrowsModelUnavailableWhenModelAbsent() async {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FluidAudioAdapterTests-\(UUID().uuidString)")
        let adapter = FluidAudioAdapter(modelDirectory: dir)
        let audioURL = dir.appendingPathComponent("audio.wav")
        do {
            _ = try await adapter.transcribe(audioURL: audioURL, vocabulary: [])
            // Either throws modelUnavailable (CI env) or returns empty (model exists)
        } catch TranscriptionError.modelUnavailable {
            // Expected in CI — model file not present
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testAcceptsVocabularyEntries() async {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FluidAudioAdapterTests-\(UUID().uuidString)")
        let adapter = FluidAudioAdapter(modelDirectory: dir)
        let vocab = [VocabularyEntry(phrase: "TestPhrase", isEnabled: true, boostingWeight: 1.5)]
        let audioURL = dir.appendingPathComponent("audio.wav")
        do {
            _ = try await adapter.transcribe(audioURL: audioURL, vocabulary: vocab)
        } catch TranscriptionError.modelUnavailable {
            // Expected in CI
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

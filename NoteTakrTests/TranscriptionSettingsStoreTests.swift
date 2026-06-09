import XCTest
@testable import NoteTakr

final class TranscriptionSettingsStoreTests: XCTestCase {

    func testMissingFileLoadsDefaultSettings() {
        let store = TranscriptionSettingsStore(fileURL: makeTempFileURL())

        XCTAssertEqual(store.load(), .default)
    }

    func testSaveAndLoadSelectedFolder() throws {
        let fileURL = makeTempFileURL()
        let store = TranscriptionSettingsStore(fileURL: fileURL)
        let settings = TranscriptionModelSettings(
            source: .localFolder(URL(fileURLWithPath: "/tmp/parakeet-tdt-0.6b-v3-coreml", isDirectory: true)),
            modelVersion: .v3
        )

        try store.save(settings)

        XCTAssertEqual(store.load(), settings)
    }

    func testSaveAndLoadAutomaticDownloadMode() throws {
        let fileURL = makeTempFileURL()
        let store = TranscriptionSettingsStore(fileURL: fileURL)
        let settings = TranscriptionModelSettings(
            source: .fluidAudioDefaultCache,
            modelVersion: .tdtCtc110m
        )

        try store.save(settings)

        XCTAssertEqual(store.load(), settings)
    }

    func testSaveAndLoadModelVersionWithoutChangingSource() throws {
        let fileURL = makeTempFileURL()
        let store = TranscriptionSettingsStore(fileURL: fileURL)
        let settings = TranscriptionModelSettings(
            source: .notConfigured,
            modelVersion: .v2
        )

        try store.save(settings)

        XCTAssertEqual(store.load(), settings)
    }

    func testCorruptedJSONFallsBackToDefault() throws {
        let fileURL = makeTempFileURL()
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("{not-json".utf8).write(to: fileURL)
        let store = TranscriptionSettingsStore(fileURL: fileURL)

        XCTAssertEqual(store.load(), .default)
    }

    private func makeTempFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("TranscriptionSettingsStoreTests-\(UUID().uuidString)")
            .appendingPathComponent("transcription-settings.json")
    }
}

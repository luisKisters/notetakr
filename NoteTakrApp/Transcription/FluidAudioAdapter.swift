import Foundation
import FluidAudio
import NoteTakrCore

protocol FluidAudioRuntimeProtocol: Sendable {
    func transcribe(audioURL: URL, settings: TranscriptionModelSettings) async throws -> String
}

actor FluidAudioRuntime: FluidAudioRuntimeProtocol {
    private var loadedSettings: TranscriptionModelSettings?
    private var manager: AsrManager?

    func transcribe(audioURL: URL, settings: TranscriptionModelSettings) async throws -> String {
        guard settings.source != .notConfigured else {
            throw TranscriptionError.modelUnavailable
        }

        let manager = try await manager(for: settings)
        var decoderState = try TdtDecoderState()
        let result = try await manager.transcribe(audioURL, decoderState: &decoderState)
        return result.text
    }

    private func manager(for settings: TranscriptionModelSettings) async throws -> AsrManager {
        if let manager, loadedSettings == settings {
            return manager
        }

        let models = try await loadModels(for: settings)
        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)
        self.manager = manager
        loadedSettings = settings
        return manager
    }

    private func loadModels(for settings: TranscriptionModelSettings) async throws -> AsrModels {
        switch settings.source {
        case .notConfigured:
            throw TranscriptionError.modelUnavailable
        case .localFolder(let url):
            switch settings.modelVersion {
            case .v3:
                return try await AsrModels.load(from: url, version: .v3)
            case .v2:
                return try await AsrModels.load(from: url, version: .v2)
            case .tdtCtc110m:
                return try await AsrModels.load(from: url, version: .tdtCtc110m)
            }
        case .fluidAudioDefaultCache:
            switch settings.modelVersion {
            case .v3:
                return try await AsrModels.downloadAndLoad(version: .v3)
            case .v2:
                return try await AsrModels.downloadAndLoad(version: .v2)
            case .tdtCtc110m:
                return try await AsrModels.downloadAndLoad(version: .tdtCtc110m)
            }
        }
    }
}

final class FluidAudioAdapter: TranscriptionEngine, @unchecked Sendable {
    private let settingsStore: TranscriptionSettingsStore
    private let runtime: any FluidAudioRuntimeProtocol

    init(
        settingsStore: TranscriptionSettingsStore,
        runtime: any FluidAudioRuntimeProtocol = FluidAudioRuntime()
    ) {
        self.settingsStore = settingsStore
        self.runtime = runtime
    }

    func transcribe(audioURL: URL, vocabulary: [VocabularyEntry]) async throws -> [TranscriptSegment] {
        let settings = settingsStore.load()
        guard settings.source != .notConfigured else {
            throw TranscriptionError.modelUnavailable
        }

        let text = try await runtime.transcribe(audioURL: audioURL, settings: settings)
        return [
            TranscriptSegment(
                timestamp: 0,
                speaker: nil,
                text: text
            ),
        ]
    }
}

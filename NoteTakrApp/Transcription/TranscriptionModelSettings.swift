import Foundation

struct TranscriptionModelSettings: Codable, Equatable, Sendable {
    enum Source: Codable, Equatable, Sendable {
        case notConfigured
        case localFolder(URL)
        case fluidAudioDefaultCache

        private enum CodingKeys: String, CodingKey {
            case type
            case path
        }

        private enum SourceType: String, Codable {
            case notConfigured
            case localFolder
            case fluidAudioDefaultCache
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(SourceType.self, forKey: .type)
            switch type {
            case .notConfigured:
                self = .notConfigured
            case .localFolder:
                let path = try container.decode(String.self, forKey: .path)
                self = .localFolder(URL(fileURLWithPath: path, isDirectory: true))
            case .fluidAudioDefaultCache:
                self = .fluidAudioDefaultCache
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .notConfigured:
                try container.encode(SourceType.notConfigured, forKey: .type)
            case .localFolder(let url):
                try container.encode(SourceType.localFolder, forKey: .type)
                try container.encode(url.path, forKey: .path)
            case .fluidAudioDefaultCache:
                try container.encode(SourceType.fluidAudioDefaultCache, forKey: .type)
            }
        }
    }

    var source: Source
    var modelVersion: FluidAudioModelVersion

    static let `default` = TranscriptionModelSettings(
        source: .notConfigured,
        modelVersion: .v3
    )
}

enum FluidAudioModelVersion: String, Codable, CaseIterable, Sendable {
    case v3
    case v2
    case tdtCtc110m
}

extension FluidAudioModelVersion {
    var displayName: String {
        switch self {
        case .v3:
            return "Parakeet v3 multilingual"
        case .v2:
            return "Parakeet v2 English"
        case .tdtCtc110m:
            return "TDT-CTC 110M smaller/faster"
        }
    }
}

final class TranscriptionSettingsStore: @unchecked Sendable {
    private let fileURL: URL
    private let decoder = JSONDecoder()
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    init(fileURL: URL = TranscriptionSettingsStore.defaultFileURL()) {
        self.fileURL = fileURL
    }

    func load() -> TranscriptionModelSettings {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .default
        }

        do {
            let data = try Data(contentsOf: fileURL)
            return try decoder.decode(TranscriptionModelSettings.self, from: data)
        } catch {
            return .default
        }
    }

    func save(_ settings: TranscriptionModelSettings) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(settings)
        try data.write(to: fileURL, options: .atomic)
    }

    static func defaultFileURL() -> URL {
        let appSupportBase = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        return appSupportBase
            .appendingPathComponent("NoteTakr", isDirectory: true)
            .appendingPathComponent("transcription-settings.json")
    }
}

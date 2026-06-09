import Foundation

/// Persists `SummarizationSettings` as JSON, mirroring `TranscriptionSettingsStore`.
public final class SummarizationSettingsStore: @unchecked Sendable {
    public let fileURL: URL
    private let decoder = JSONDecoder()
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() -> SummarizationSettings {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let settings = try? decoder.decode(SummarizationSettings.self, from: data)
        else {
            return .default
        }
        return settings
    }

    public func save(_ settings: SummarizationSettings) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(settings)
        try data.write(to: fileURL, options: .atomic)
    }
}

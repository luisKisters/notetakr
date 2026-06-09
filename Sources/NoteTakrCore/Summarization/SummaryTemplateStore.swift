import Foundation

/// Persists summary templates as JSON, mirroring `VocabularyStore`. Seeds the
/// built-in defaults on first load (missing or empty file).
public final class SummaryTemplateStore: @unchecked Sendable {
    public let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL) {
        self.fileURL = fileURL
        encoder = JSONEncoder()
        decoder = JSONDecoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public func load() -> [SummaryTemplate] {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let templates = try? decoder.decode([SummaryTemplate].self, from: data),
              !templates.isEmpty
        else {
            let defaults = SummaryTemplate.defaults
            try? save(defaults)
            return defaults
        }
        return templates
    }

    public func save(_ templates: [SummaryTemplate]) throws {
        let data = try encoder.encode(templates)
        let dir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }
}

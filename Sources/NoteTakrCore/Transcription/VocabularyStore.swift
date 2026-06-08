import Foundation

public final class VocabularyStore: @unchecked Sendable {
    public let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL) {
        self.fileURL = fileURL
        encoder = JSONEncoder()
        decoder = JSONDecoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public func save(_ entries: [VocabularyEntry]) throws {
        let data = try encoder.encode(entries)
        let dir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }

    public func load() throws -> [VocabularyEntry] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode([VocabularyEntry].self, from: data)
    }

    public func enabledEntries() throws -> [VocabularyEntry] {
        try load().filter { $0.isEnabled }
    }
}

import Foundation

/// Lightweight file-backed store for the global custom-vocabulary list.
/// Stores terms as a plain JSON array of strings so it is easily testable
/// on Linux (no AppKit / macOS-only APIs).
public final class GlobalVocabularyStore: @unchecked Sendable {
    public let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL) {
        self.fileURL = fileURL
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder = JSONDecoder()
    }

    public func load() -> [String] {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let terms = try? decoder.decode([String].self, from: data)
        else { return [] }
        return terms
    }

    public func save(_ terms: [String]) throws {
        let dir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try encoder.encode(terms)
        try data.write(to: fileURL, options: .atomic)
    }

    public func add(_ term: String) throws {
        let trimmed = term.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        var terms = load()
        guard !terms.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
        terms.append(trimmed)
        try save(terms)
    }

    public func remove(_ term: String) throws {
        var terms = load()
        terms.removeAll { $0.caseInsensitiveCompare(term) == .orderedSame }
        try save(terms)
    }
}

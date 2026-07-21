import Foundation

public final class SyncOutbox: @unchecked Sendable {
    public let rootURL: URL
    public let outboxURL: URL

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(rootURL: URL) {
        self.rootURL = rootURL
        self.outboxURL = rootURL
            .appendingPathComponent("NoteTakr", isDirectory: true)
            .appendingPathComponent("Outbox", isDirectory: true)

        encoder = JSONEncoder()
        decoder = JSONDecoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public func fileURL(for localId: String) -> URL {
        outboxURL.appendingPathComponent("\(Self.filenameComponent(for: localId)).json")
    }

    public func enqueue(_ payload: MeetingPayload) throws {
        try FileManager.default.createDirectory(at: outboxURL, withIntermediateDirectories: true)
        let item = StoredOutboxItem(payload: payload, enqueuedAt: Date())
        let data = try encoder.encode(item)
        try data.write(to: fileURL(for: payload.localId), options: .atomic)
    }

    public func pending() throws -> [MeetingPayload] {
        guard FileManager.default.fileExists(atPath: outboxURL.path) else { return [] }
        let files = try FileManager.default.contentsOfDirectory(
            at: outboxURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        )
        let items = try files
            .filter { $0.pathExtension == "json" }
            .map { url -> StoredOutboxItem in
                let data = try Data(contentsOf: url)
                if let item = try? decoder.decode(StoredOutboxItem.self, from: data) {
                    return item
                }
                let payload = try decoder.decode(MeetingPayload.self, from: data)
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                return StoredOutboxItem(
                    payload: payload,
                    enqueuedAt: values?.contentModificationDate ?? .distantPast
                )
            }
        return items
            .sorted {
                if $0.enqueuedAt != $1.enqueuedAt {
                    return $0.enqueuedAt < $1.enqueuedAt
                }
                return $0.payload.localId < $1.payload.localId
            }
            .map(\.payload)
    }

    public func complete(localId: String) throws {
        let url = fileURL(for: localId)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    private static func filenameComponent(for localId: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        let encoded = localId.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        return encoded.isEmpty ? "_" : encoded
    }
}

private struct StoredOutboxItem: Codable {
    var payload: MeetingPayload
    var enqueuedAt: Date
}

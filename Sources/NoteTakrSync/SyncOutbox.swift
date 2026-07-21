import Foundation

public enum SyncOutboxOperation: Equatable, Sendable {
    case upsert(MeetingPayload)
    case delete(localId: String)

    public var localId: String {
        switch self {
        case .upsert(let payload):
            return payload.localId
        case .delete(let localId):
            return localId
        }
    }
}

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

    public func enqueueDelete(localId: String) throws {
        try FileManager.default.createDirectory(at: outboxURL, withIntermediateDirectories: true)
        let item = StoredOutboxItem(deleteLocalId: localId, enqueuedAt: Date())
        let data = try encoder.encode(item)
        try data.write(to: fileURL(for: localId), options: .atomic)
    }

    public func pending() throws -> [MeetingPayload] {
        try pendingOperations().compactMap { operation in
            guard case .upsert(let payload) = operation else { return nil }
            return payload
        }
    }

    public func pendingOperations() throws -> [SyncOutboxOperation] {
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
        return try items
            .sorted {
                if $0.enqueuedAt != $1.enqueuedAt {
                    return $0.enqueuedAt < $1.enqueuedAt
                }
                return $0.localId < $1.localId
            }
            .map { try $0.operationValue() }
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

private enum StoredOutboxOperation: String, Codable {
    case upsert
    case delete
}

private struct StoredOutboxItem: Codable {
    var operation: StoredOutboxOperation
    var payload: MeetingPayload?
    var localId: String
    var enqueuedAt: Date

    enum CodingKeys: String, CodingKey {
        case operation
        case payload
        case localId
        case enqueuedAt
    }

    init(payload: MeetingPayload, enqueuedAt: Date) {
        self.operation = .upsert
        self.payload = payload
        self.localId = payload.localId
        self.enqueuedAt = enqueuedAt
    }

    init(deleteLocalId localId: String, enqueuedAt: Date) {
        self.operation = .delete
        self.payload = nil
        self.localId = localId
        self.enqueuedAt = enqueuedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        operation = try container.decodeIfPresent(StoredOutboxOperation.self, forKey: .operation) ?? .upsert
        payload = try container.decodeIfPresent(MeetingPayload.self, forKey: .payload)
        if let localId = try container.decodeIfPresent(String.self, forKey: .localId) {
            self.localId = localId
        } else if let payload {
            self.localId = payload.localId
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.localId,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Stored outbox item is missing localId"
                )
            )
        }
        enqueuedAt = try container.decodeIfPresent(Date.self, forKey: .enqueuedAt) ?? .distantPast
    }

    func operationValue() throws -> SyncOutboxOperation {
        switch operation {
        case .upsert:
            guard let payload else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: [],
                        debugDescription: "Stored upsert item is missing payload"
                    )
                )
            }
            return .upsert(payload)
        case .delete:
            return .delete(localId: localId)
        }
    }
}

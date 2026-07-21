import Foundation
import NoteTakrCore
import NoteTakrKit

public struct MeetingPayload: Codable, Equatable, Sendable {
    public struct Participant: Codable, Equatable, Sendable {
        public var name: String
        public var email: String?
        public var crm: String?

        public init(name: String, email: String? = nil, crm: String? = nil) {
            self.name = name
            self.email = email
            self.crm = crm
        }
    }

    public struct TranscriptSegment: Codable, Equatable, Sendable {
        public var seq: Int
        public var startMs: Int
        public var speaker: String?
        public var text: String

        public init(seq: Int, startMs: Int, speaker: String? = nil, text: String) {
            self.seq = seq
            self.startMs = startMs
            self.speaker = speaker
            self.text = text
        }
    }

    public var localId: String
    public var title: String
    public var startedAt: Date
    public var calendarEventId: String?
    public var participants: [Participant]
    public var markdownBody: String
    public var transcriptSegments: [TranscriptSegment]
    public var crmPushOptOut: Bool?
    public var contentHash: String

    public init(
        localId: String,
        title: String,
        startedAt: Date,
        calendarEventId: String? = nil,
        participants: [Participant] = [],
        markdownBody: String,
        transcriptSegments: [TranscriptSegment] = [],
        crmPushOptOut: Bool? = nil,
        contentHash: String
    ) {
        self.localId = localId
        self.title = title
        self.startedAt = startedAt
        self.calendarEventId = calendarEventId
        self.participants = participants
        self.markdownBody = markdownBody
        self.transcriptSegments = transcriptSegments
        self.crmPushOptOut = crmPushOptOut
        self.contentHash = contentHash
    }
}

public enum SyncEnvelope {
    public static func payload(
        session: NoteTakrCore.MeetingSession,
        note: NoteTakrKit.MeetingNote
    ) throws -> MeetingPayload {
        let transcript = session.transcriptSegments.enumerated().map { offset, segment in
            MeetingPayload.TranscriptSegment(
                seq: offset,
                startMs: Int((segment.timestamp * 1_000).rounded()),
                speaker: trimmedNonEmpty(segment.speaker),
                text: segment.text
            )
        }

        var payload = MeetingPayload(
            localId: session.id.uuidString,
            title: note.title,
            startedAt: note.date,
            calendarEventId: trimmedNonEmpty(note.calendarEvent) ?? trimmedNonEmpty(session.linkedEventID),
            participants: note.participants.map {
                MeetingPayload.Participant(
                    name: $0.name,
                    email: trimmedNonEmpty($0.email),
                    crm: trimmedNonEmpty($0.crm)
                )
            },
            markdownBody: note.body,
            transcriptSegments: transcript,
            crmPushOptOut: note.crmPushOptOut,
            contentHash: ""
        )
        payload.contentHash = try contentHash(for: payload)
        return payload
    }

    private struct HashContent: Encodable {
        var localId: String
        var title: String
        var startedAt: Date
        var calendarEventId: String?
        var participants: [MeetingPayload.Participant]
        var markdownBody: String
        var transcriptSegments: [MeetingPayload.TranscriptSegment]
    }

    private static func contentHash(for payload: MeetingPayload) throws -> String {
        let content = HashContent(
            localId: payload.localId,
            title: payload.title,
            startedAt: payload.startedAt,
            calendarEventId: payload.calendarEventId,
            participants: payload.participants,
            markdownBody: payload.markdownBody,
            transcriptSegments: payload.transcriptSegments
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(content)
        return SHA256.hexDigest(for: data)
    }

    private static func trimmedNonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

private enum SHA256 {
    private static let initialHash: [UInt32] = [
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
        0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
    ]

    private static let roundConstants: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
        0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
        0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
        0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
        0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
        0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
        0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
        0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
        0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ]

    static func hexDigest(for data: Data) -> String {
        digest(for: [UInt8](data)).map { String(format: "%02x", $0) }.joined()
    }

    private static func digest(for bytes: [UInt8]) -> [UInt8] {
        var message = bytes
        let bitLength = UInt64(message.count) * 8
        message.append(0x80)
        while message.count % 64 != 56 {
            message.append(0)
        }
        message.append(contentsOf: bitLength.bigEndianBytes)

        var hash = initialHash
        var words = Array(repeating: UInt32(0), count: 64)

        for chunkStart in stride(from: 0, to: message.count, by: 64) {
            for i in 0..<16 {
                let j = chunkStart + i * 4
                words[i] = UInt32(message[j]) << 24
                    | UInt32(message[j + 1]) << 16
                    | UInt32(message[j + 2]) << 8
                    | UInt32(message[j + 3])
            }
            for i in 16..<64 {
                words[i] = smallSigma1(words[i - 2])
                    &+ words[i - 7]
                    &+ smallSigma0(words[i - 15])
                    &+ words[i - 16]
            }

            var a = hash[0]
            var b = hash[1]
            var c = hash[2]
            var d = hash[3]
            var e = hash[4]
            var f = hash[5]
            var g = hash[6]
            var h = hash[7]

            for i in 0..<64 {
                let temp1 = h
                    &+ bigSigma1(e)
                    &+ choice(e, f, g)
                    &+ roundConstants[i]
                    &+ words[i]
                let temp2 = bigSigma0(a) &+ majority(a, b, c)
                h = g
                g = f
                f = e
                e = d &+ temp1
                d = c
                c = b
                b = a
                a = temp1 &+ temp2
            }

            hash[0] = hash[0] &+ a
            hash[1] = hash[1] &+ b
            hash[2] = hash[2] &+ c
            hash[3] = hash[3] &+ d
            hash[4] = hash[4] &+ e
            hash[5] = hash[5] &+ f
            hash[6] = hash[6] &+ g
            hash[7] = hash[7] &+ h
        }

        return hash.flatMap(\.bigEndianBytes)
    }

    private static func rotateRight(_ value: UInt32, by count: UInt32) -> UInt32 {
        (value >> count) | (value << (32 - count))
    }

    private static func bigSigma0(_ value: UInt32) -> UInt32 {
        rotateRight(value, by: 2) ^ rotateRight(value, by: 13) ^ rotateRight(value, by: 22)
    }

    private static func bigSigma1(_ value: UInt32) -> UInt32 {
        rotateRight(value, by: 6) ^ rotateRight(value, by: 11) ^ rotateRight(value, by: 25)
    }

    private static func smallSigma0(_ value: UInt32) -> UInt32 {
        rotateRight(value, by: 7) ^ rotateRight(value, by: 18) ^ (value >> 3)
    }

    private static func smallSigma1(_ value: UInt32) -> UInt32 {
        rotateRight(value, by: 17) ^ rotateRight(value, by: 19) ^ (value >> 10)
    }

    private static func choice(_ x: UInt32, _ y: UInt32, _ z: UInt32) -> UInt32 {
        (x & y) ^ (~x & z)
    }

    private static func majority(_ x: UInt32, _ y: UInt32, _ z: UInt32) -> UInt32 {
        (x & y) ^ (x & z) ^ (y & z)
    }
}

private extension FixedWidthInteger {
    var bigEndianBytes: [UInt8] {
        withUnsafeBytes(of: self.bigEndian) { Array($0) }
    }
}

import Foundation
import XCTest
import NoteTakrCore
import NoteTakrKit
@testable import NoteTakrSync

final class FileSpoolSyncBackendTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileSpoolSyncBackendTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testUpsertWritesPayloadToSpool() async throws {
        let backend = FileSpoolSyncBackend(rootURL: tempDir, pollInterval: 0.01)
        let payload = try makePayload(localId: "11111111-1111-1111-1111-111111111111")

        try await backend.upsertMeeting(payload)

        let data = try Data(contentsOf: backend.payloadURL(for: payload.localId))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(MeetingPayload.self, from: data)
        XCTAssertEqual(decoded, payload)
    }

    func testSummaryFileEmitsUpdate() async throws {
        let backend = FileSpoolSyncBackend(rootURL: tempDir, pollInterval: 0.01)
        try FileManager.default.createDirectory(at: backend.summariesURL, withIntermediateDirectories: true)

        let listener = Task {
            var iterator = backend.summaryUpdates().makeAsyncIterator()
            return await iterator.next()
        }

        let update = SummaryUpdate(
            localId: "22222222-2222-2222-2222-222222222222",
            text: "Server summary"
        )
        let encoder = JSONEncoder()
        try encoder.encode(update).write(to: backend.summaryURL(for: update.localId), options: .atomic)

        let received = await listener.value
        XCTAssertEqual(received, update)
    }

    func testUnavailableBackendReportsMissingConfiguration() async {
        let backend = UnavailableSyncBackend(missingConfiguration: [
            "CONVEX_DEPLOYMENT_URL",
            "CLERK_PUBLISHABLE_KEY",
        ])

        do {
            try await backend.signInWithGoogle()
            XCTFail("Expected sign-in to fail when sync credentials are missing.")
        } catch let error as UnavailableSyncBackendError {
            XCTAssertEqual(
                error,
                .missingConfiguration(["CONVEX_DEPLOYMENT_URL", "CLERK_PUBLISHABLE_KEY"])
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func makePayload(localId: String, body: String = "body") throws -> MeetingPayload {
        let id = UUID(uuidString: localId)!
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let session = MeetingSession(
            id: id,
            title: "Spool",
            date: date,
            status: .stopped,
            transcriptSegments: [
                TranscriptSegment(timestamp: 0, speaker: "Ada", text: "Hello")
            ]
        )
        let note = MeetingNote(
            id: localId,
            title: "Spool",
            date: date,
            participants: [
                NoteTakrKit.Participant(name: "Ada", email: "ada@example.test")
            ],
            body: body
        )
        return try SyncEnvelope.payload(session: session, note: note)
    }
}

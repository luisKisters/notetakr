import Foundation
import XCTest
import NoteTakrKit
@testable import NoteTakrSync

final class ConvexPeopleCacheSourceTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConvexPeopleCacheSourceTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testLoadsPeopleFromCachedSnapshot() throws {
        let source = ConvexPeopleCacheSource(rootURL: tempDir)
        try source.refresh(people: [
            ConvexCachedPerson(
                remoteId: "person-1",
                name: "Ada Lovelace",
                emails: ["ADA@Analytical.Example"],
                company: "Analytical Engines"
            )
        ])

        XCTAssertEqual(
            source.allPeople(),
            [
                Person(
                    name: "Ada Lovelace",
                    emails: ["ada@analytical.example"],
                    company: "Analytical Engines",
                    sourceRefs: [SourceRef(provider: "crm", remoteId: "person-1")]
                )
            ]
        )
    }

    func testMissingCacheFileYieldsEmptySourceWithoutError() {
        let source = ConvexPeopleCacheSource(rootURL: tempDir)

        XCTAssertEqual(source.allPeople(), [])
        XCTAssertEqual(source.search("Ada"), [])
    }

    func testRefreshRewritesSnapshotAtomically() throws {
        let source = ConvexPeopleCacheSource(rootURL: tempDir)
        try source.refresh(people: [
            ConvexCachedPerson(
                remoteId: "old-person",
                name: "Old Person",
                emails: ["old@example.test"]
            )
        ])

        try source.refresh(people: [
            ConvexCachedPerson(
                remoteId: "new-person",
                name: "New Person",
                emails: ["new@example.test"]
            )
        ])

        XCTAssertEqual(
            source.allPeople(),
            [
                Person(
                    name: "New Person",
                    emails: ["new@example.test"],
                    sourceRefs: [SourceRef(provider: "crm", remoteId: "new-person")]
                )
            ]
        )

        let data = try Data(contentsOf: source.snapshotURL)
        let decoded = try JSONDecoder().decode([ConvexCachedPerson].self, from: data)
        XCTAssertEqual(decoded.map(\.remoteId), ["new-person"])
    }
}

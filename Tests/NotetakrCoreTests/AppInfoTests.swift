import XCTest
@testable import NotetakrCore

final class AppInfoTests: XCTestCase {
    func testProductName() {
        XCTAssertEqual(AppInfo.name, "Notetakr")
    }

    func testVersionIsSemantic() {
        let parts = AppInfo.version.split(separator: ".")
        XCTAssertEqual(parts.count, 3, "version should be MAJOR.MINOR.PATCH")
        XCTAssertTrue(parts.allSatisfy { Int($0) != nil }, "version components should be numeric")
    }

    func testTaglineIsNotEmpty() {
        XCTAssertFalse(AppInfo.tagline.isEmpty)
    }
}

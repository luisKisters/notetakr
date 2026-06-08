import XCTest
@testable import NoteTakrCore

final class NoteTakrCoreTests: XCTestCase {
    func testVersionIsNotEmpty() {
        XCTAssertFalse(NoteTakrCore.version.isEmpty)
    }
}

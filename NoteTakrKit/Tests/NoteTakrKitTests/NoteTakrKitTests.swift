import XCTest
@testable import NoteTakrKit

final class NoteTakrKitTests: XCTestCase {
    func testVersionIsNonEmpty() {
        XCTAssertFalse(NoteTakrKitVersion.version.isEmpty)
    }
}

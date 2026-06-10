import XCTest
@testable import NoteTakrKit

final class NoteTakrKitTests: XCTestCase {
    func testVersionIsNonEmpty() {
        XCTAssertFalse(NoteTakrKit.version.isEmpty)
    }
}

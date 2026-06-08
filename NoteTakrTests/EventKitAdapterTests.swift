import XCTest
import EventKit
import NoteTakrCore
@testable import NoteTakr

final class EventKitAdapterTests: XCTestCase {

    func testEventKitAdapterConformsToProtocol() {
        let adapter: any CalendarAdapter = EventKitCalendarAdapter()
        _ = adapter
    }

    func testEventKitAdapterInstantiates() {
        let adapter = EventKitCalendarAdapter()
        XCTAssertNotNil(adapter)
    }
}

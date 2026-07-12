import XCTest
import Contacts
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

    func testContactNameResolverDoesNotQueryWithoutAuthorization() {
        var lookupCount = 0
        let resolver = ContactNameResolver(
            authorizationStatus: { .denied },
            contactLookup: { _, _ in
                lookupCount += 1
                return [Self.contact(givenName: "Private", familyName: "Person")]
            }
        )

        XCTAssertNil(resolver.displayName(forEmail: "person@example.com"))
        XCTAssertEqual(lookupCount, 0, "Denied Contacts access must never touch the contact store")
    }

    func testContactNameResolverDoesNotQueryWhileConsentIsUndetermined() {
        var lookupCount = 0
        let resolver = ContactNameResolver(
            authorizationStatus: { .notDetermined },
            contactLookup: { _, _ in
                lookupCount += 1
                return []
            }
        )

        XCTAssertNil(resolver.displayName(forEmail: "person@example.com"))
        XCTAssertEqual(lookupCount, 0, "Calendar reads must not trigger an implicit Contacts prompt")
    }

    func testContactNameResolverUsesAuthorizedContactFullName() {
        var lookupCount = 0
        let resolver = ContactNameResolver(
            authorizationStatus: { .authorized },
            contactLookup: { _, keys in
                lookupCount += 1
                XCTAssertFalse(keys.isEmpty)
                return [Self.contact(givenName: "Ada", familyName: "Lovelace")]
            }
        )

        XCTAssertEqual(resolver.displayName(forEmail: "  ada@example.com "), "Ada Lovelace")
        XCTAssertEqual(lookupCount, 1)
    }

    func testContactNameResolverSafelyFallsBackWhenNoContactMatches() {
        let resolver = ContactNameResolver(
            authorizationStatus: { .authorized },
            contactLookup: { _, _ in [] }
        )

        XCTAssertNil(resolver.displayName(forEmail: "unknown@example.com"))
    }

    func testContactNameResolverSafelyFallsBackWhenLookupThrows() {
        struct LookupError: Error {}
        let resolver = ContactNameResolver(
            authorizationStatus: { .authorized },
            contactLookup: { _, _ in throw LookupError() }
        )

        XCTAssertNil(resolver.displayName(forEmail: "unknown@example.com"))
    }

    func testAttendeeDisplayNamePrefersAuthorizedContactName() {
        let resolver = StubContactNameResolver(name: "Contacts Name")

        XCTAssertEqual(
            NoteTakrCore.Participant.resolvedDisplayName(
                calendarName: "Calendar Name",
                email: "person@example.com",
                contactNameResolver: resolver
            ),
            "Contacts Name"
        )
    }

    func testAttendeeDisplayNamePreservesSafeCalendarFallback() {
        let resolver = StubContactNameResolver(name: nil)

        XCTAssertEqual(
            NoteTakrCore.Participant.resolvedDisplayName(
                calendarName: "Calendar Name",
                email: "person@example.com",
                contactNameResolver: resolver
            ),
            "Calendar Name"
        )
    }

    func testAttendeeDisplayNameHasSafeEmailDerivedFallback() {
        let resolver = StubContactNameResolver(name: nil)

        XCTAssertEqual(
            NoteTakrCore.Participant.resolvedDisplayName(
                calendarName: nil,
                email: "grace_hopper@example.com",
                contactNameResolver: resolver
            ),
            "Grace Hopper"
        )
    }

    private static func contact(givenName: String, familyName: String) -> CNContact {
        let contact = CNMutableContact()
        contact.givenName = givenName
        contact.familyName = familyName
        return contact.copy() as! CNContact
    }
}

private struct StubContactNameResolver: ContactNameResolving {
    let name: String?

    func displayName(forEmail email: String) -> String? { name }
}

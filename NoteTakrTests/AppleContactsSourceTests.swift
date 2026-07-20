import XCTest
import Contacts
import NoteTakrKit
@testable import NoteTakr

final class AppleContactsSourceTests: XCTestCase {
    func testDoesNotQueryContactsWithoutAuthorization() {
        var fetchCount = 0
        let source = AppleContactsSource(
            authorizationStatus: { .denied },
            fetchContacts: { _ in
                fetchCount += 1
                return [Self.contact(givenName: "Private", familyName: "Person", emails: ["private@example.com"])]
            }
        )

        XCTAssertEqual(source.allPeople(), [])
        XCTAssertEqual(fetchCount, 0, "Denied Contacts access must never touch the contact store")
    }

    func testDoesNotQueryWhileConsentUndetermined() {
        var fetchCount = 0
        let source = AppleContactsSource(
            authorizationStatus: { .notDetermined },
            fetchContacts: { _ in
                fetchCount += 1
                return []
            }
        )

        XCTAssertEqual(source.allPeople(), [])
        XCTAssertEqual(fetchCount, 0, "Undetermined Contacts consent must never trigger a permission prompt")
    }

    func testAuthorizedContactsMapToPersonsWithLowercasedEmails() {
        var fetchCount = 0
        let source = AppleContactsSource(
            authorizationStatus: { .authorized },
            fetchContacts: { keys in
                fetchCount += 1
                XCTAssertFalse(keys.isEmpty)
                return [Self.contact(givenName: "Grace", familyName: "Hopper", emails: ["Grace@Navy.mil"])]
            }
        )

        XCTAssertEqual(source.allPeople(), [Person(name: "Grace Hopper", emails: ["grace@navy.mil"])])
        XCTAssertEqual(fetchCount, 1)
    }

    private static func contact(givenName: String, familyName: String, emails: [String]) -> CNContact {
        let contact = CNMutableContact()
        contact.givenName = givenName
        contact.familyName = familyName
        contact.emailAddresses = emails.map {
            CNLabeledValue(label: CNLabelWork, value: $0 as NSString)
        }
        return contact.copy() as! CNContact
    }
}

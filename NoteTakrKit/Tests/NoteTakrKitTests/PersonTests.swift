import XCTest
@testable import NoteTakrKit

final class PersonTests: XCTestCase {
    func testEmailsAreLowercasedAndDeduplicatedOnInit() {
        let person = Person(name: "Ada Lovelace", emails: ["A@x.com", "a@x.com"])

        XCTAssertEqual(person.emails, ["a@x.com"])
    }

    func testCompanyIsDerivedFromCustomDomain() {
        let person = Person(name: "Sarah Chen", emails: ["sarah@acme.com"])

        XCTAssertEqual(person.company, "Acme")
    }

    func testCompanyIsNilForPublicEmailDomains() {
        let gmail = Person(name: "Gmail", emails: ["person@gmail.com"])
        let icloud = Person(name: "iCloud", emails: ["person@icloud.com"])
        let outlook = Person(name: "Outlook", emails: ["person@outlook.com"])

        XCTAssertNil(gmail.company)
        XCTAssertNil(icloud.company)
        XCTAssertNil(outlook.company)
    }
}

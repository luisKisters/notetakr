import XCTest
@testable import NoteTakrKit

final class FrontmatterSerializerTests: XCTestCase {

    // MARK: - Helpers

    private static let tz = TimeZone(secondsFromGMT: 2 * 3600)!

    private func makeDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, tz: TimeZone = FrontmatterSerializerTests.tz) -> Date {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day
        c.hour = hour; c.minute = minute; c.second = 0
        c.timeZone = tz
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    // MARK: - Round-trip: full note

    func testRoundTripFullNote() throws {
        let date = makeDate(2026, 6, 10, 14, 0)
        let end  = makeDate(2026, 6, 10, 14, 45)
        let note = MeetingNote(
            id: "9F2C1234",
            title: "Weekly Sync — Acme GmbH",
            date: date,
            end: end,
            calendarEvent: "ABC123@1718020800",
            participants: [
                Participant(name: "Luis Kisters", email: "luis@example.com"),
                Participant(name: "Sarah Chen"),
            ],
            location: .zoom,
            inPerson: false,
            transcribe: true,
            language: .auto,
            vocabulary: ["Acme", "Müller"],
            body: "## Notes\n\nSome content here."
        )
        let rendered = FrontmatterSerializer.render(note: note)
        let parsed = FrontmatterSerializer.parse(fileText: rendered)
        XCTAssertEqual(parsed, note)
    }

    func testRoundTripMinimalNote() {
        let date = makeDate(2026, 1, 1, 9, 0)
        let note = MeetingNote(id: "ABCD", title: "Standup", date: date)
        let rendered = FrontmatterSerializer.render(note: note)
        let parsed = FrontmatterSerializer.parse(fileText: rendered)
        XCTAssertEqual(parsed, note)
    }

    // MARK: - Title edge cases

    func testTitleWithUmlauts() {
        let date = makeDate(2026, 6, 10, 10, 0)
        let note = MeetingNote(id: "X1", title: "Müller & Söhne: Jahresgespräch", date: date)
        let rendered = FrontmatterSerializer.render(note: note)
        let parsed = FrontmatterSerializer.parse(fileText: rendered)
        XCTAssertEqual(parsed.title, "Müller & Söhne: Jahresgespräch")
    }

    func testTitleWithEmDash() {
        let date = makeDate(2026, 6, 10, 10, 0)
        let note = MeetingNote(id: "X2", title: "Weekly — Team", date: date)
        let rendered = FrontmatterSerializer.render(note: note)
        let parsed = FrontmatterSerializer.parse(fileText: rendered)
        XCTAssertEqual(parsed.title, "Weekly — Team")
    }

    func testTitleWithQuotes() {
        let date = makeDate(2026, 6, 10, 10, 0)
        let note = MeetingNote(id: "X3", title: "Review \"Alpha\" release", date: date)
        let rendered = FrontmatterSerializer.render(note: note)
        let parsed = FrontmatterSerializer.parse(fileText: rendered)
        XCTAssertEqual(parsed.title, "Review \"Alpha\" release")
    }

    func testTitleWithColon() {
        let date = makeDate(2026, 6, 10, 10, 0)
        let note = MeetingNote(id: "X4", title: "Q2: Planning", date: date)
        let rendered = FrontmatterSerializer.render(note: note)
        let parsed = FrontmatterSerializer.parse(fileText: rendered)
        XCTAssertEqual(parsed.title, "Q2: Planning")
    }

    // MARK: - Unknown key preservation

    func testUnknownKeyPreservation() {
        let fileText = """
        ---
        id: ZZ99
        title: Test
        date: 2026-06-10T10:00:00+02:00
        custom_field: some value
        another: 42
        ---
        Body text.
        """
        let parsed = FrontmatterSerializer.parse(fileText: fileText)
        XCTAssertEqual(parsed.unknownFrontmatterKeys.count, 2)
        let rendered = FrontmatterSerializer.render(note: parsed)
        XCTAssertTrue(rendered.contains("custom_field: some value"))
        XCTAssertTrue(rendered.contains("another: 42"))
    }

    // MARK: - Body with --- lines

    func testBodyContainingTripleDash() {
        let fileText = """
        ---
        id: AA01
        title: Tricky
        date: 2026-06-10T10:00:00+02:00
        ---
        First paragraph.

        ---

        Second paragraph.
        """
        let parsed = FrontmatterSerializer.parse(fileText: fileText)
        XCTAssertTrue(parsed.body.contains("---"), "body should contain triple-dash lines")
        XCTAssertEqual(parsed.id, "AA01")
    }

    // MARK: - Empty body

    func testEmptyBody() {
        let date = makeDate(2026, 6, 10, 10, 0)
        let note = MeetingNote(id: "E1", title: "Empty", date: date, body: "")
        let rendered = FrontmatterSerializer.render(note: note)
        let parsed = FrontmatterSerializer.parse(fileText: rendered)
        XCTAssertEqual(parsed.body, "")
    }

    // MARK: - Missing optional keys

    func testMissingOptionalKeys() {
        let fileText = """
        ---
        id: B1
        title: Minimal
        date: 2026-06-10T10:00:00+02:00
        ---
        """
        let parsed = FrontmatterSerializer.parse(fileText: fileText)
        XCTAssertNil(parsed.end)
        XCTAssertNil(parsed.calendarEvent)
        XCTAssertTrue(parsed.participants.isEmpty)
        XCTAssertNil(parsed.location)
        XCTAssertNil(parsed.inPerson)
        XCTAssertNil(parsed.transcribe)
        XCTAssertNil(parsed.language)
        XCTAssertTrue(parsed.vocabulary.isEmpty)
    }

    // MARK: - Body-only file

    func testBodyOnlyFile() {
        let fileText = "Just plain text, no frontmatter."
        let parsed = FrontmatterSerializer.parse(fileText: fileText)
        XCTAssertEqual(parsed.body, fileText)
        XCTAssertTrue(parsed.id.isEmpty)
    }

    // MARK: - Malformed frontmatter degrades to body-only

    func testMalformedFrontmatterDegradesToBodyOnly() {
        let fileText = """
        ---
        not: valid yaml {{{
        missing_id: true
        ---
        content
        """
        let parsed = FrontmatterSerializer.parse(fileText: fileText)
        // No id/title → body-only
        XCTAssertTrue(parsed.id.isEmpty)
        XCTAssertNoThrow(_ = FrontmatterSerializer.parse(fileText: fileText))
    }

    func testNoClosingDelimiterDegradesToBodyOnly() {
        let fileText = """
        ---
        id: Z1
        title: Unclosed
        date: 2026-06-10T10:00:00+02:00
        body text here
        """
        let parsed = FrontmatterSerializer.parse(fileText: fileText)
        XCTAssertTrue(parsed.id.isEmpty)
    }

    // MARK: - Participant forms

    func testParticipantWithEmail() {
        let fileText = """
        ---
        id: P1
        title: Meeting
        date: 2026-06-10T10:00:00+02:00
        participants: [Luis Kisters <luis@example.com>, Sarah Chen]
        ---
        """
        let parsed = FrontmatterSerializer.parse(fileText: fileText)
        XCTAssertEqual(parsed.participants.count, 2)
        XCTAssertEqual(parsed.participants[0].email, "luis@example.com")
        XCTAssertNil(parsed.participants[1].email)
    }

    func testParticipantBlockStyle() {
        let fileText = """
        ---
        id: P2
        title: Meeting
        date: 2026-06-10T10:00:00+02:00
        participants:
          - Alice
          - Bob <bob@test.com>
        ---
        """
        let parsed = FrontmatterSerializer.parse(fileText: fileText)
        XCTAssertEqual(parsed.participants.count, 2)
        XCTAssertEqual(parsed.participants[0].name, "Alice")
        XCTAssertEqual(parsed.participants[1].email, "bob@test.com")
    }

    // MARK: - Location values

    func testAllLocationValues() {
        let locations: [Location] = [.zoom, .meet, .teams, .inPerson, .none]
        for loc in locations {
            let date = makeDate(2026, 6, 10, 10, 0)
            let note = MeetingNote(id: "L1", title: "Test", date: date, location: loc)
            let rendered = FrontmatterSerializer.render(note: note)
            let parsed = FrontmatterSerializer.parse(fileText: rendered)
            XCTAssertEqual(parsed.location, loc, "location \(loc.rawValue) should round-trip")
        }
    }

    // MARK: - Language

    func testLanguageAuto() {
        let date = makeDate(2026, 6, 10, 10, 0)
        let note = MeetingNote(id: "L2", title: "T", date: date, language: .auto)
        let rendered = FrontmatterSerializer.render(note: note)
        let parsed = FrontmatterSerializer.parse(fileText: rendered)
        XCTAssertEqual(parsed.language, .auto)
    }

    func testLanguageCode() {
        let date = makeDate(2026, 6, 10, 10, 0)
        let note = MeetingNote(id: "L3", title: "T", date: date, language: .code("de"))
        let rendered = FrontmatterSerializer.render(note: note)
        let parsed = FrontmatterSerializer.parse(fileText: rendered)
        XCTAssertEqual(parsed.language, .code("de"))
    }

    // MARK: - Vocabulary

    func testVocabularyFlowList() {
        let fileText = """
        ---
        id: V1
        title: Meeting
        date: 2026-06-10T10:00:00+02:00
        vocabulary: [Acme, Müller, SwiftUI]
        ---
        """
        let parsed = FrontmatterSerializer.parse(fileText: fileText)
        XCTAssertEqual(parsed.vocabulary, ["Acme", "Müller", "SwiftUI"])
    }

    func testVocabularyBlockList() {
        let fileText = """
        ---
        id: V2
        title: Meeting
        date: 2026-06-10T10:00:00+02:00
        vocabulary:
          - Acme
          - Müller
        ---
        """
        let parsed = FrontmatterSerializer.parse(fileText: fileText)
        XCTAssertEqual(parsed.vocabulary, ["Acme", "Müller"])
    }

    // MARK: - Round-trip: all field combinations

    func testRoundTripAllLocations() {
        let date = makeDate(2026, 6, 10, 10, 0)
        for loc in Location.allCases {
            let note = MeetingNote(id: "RT\(loc.rawValue)", title: "T", date: date, location: loc)
            let rt = FrontmatterSerializer.parse(fileText: FrontmatterSerializer.render(note: note))
            XCTAssertEqual(rt.location, loc)
        }
    }

    func testRoundTripBooleans() {
        let date = makeDate(2026, 6, 10, 10, 0)
        for ip in [true, false] {
            for tr in [true, false] {
                let note = MeetingNote(id: "B\(ip)\(tr)", title: "T", date: date, inPerson: ip, transcribe: tr)
                let rt = FrontmatterSerializer.parse(fileText: FrontmatterSerializer.render(note: note))
                XCTAssertEqual(rt.inPerson, ip)
                XCTAssertEqual(rt.transcribe, tr)
            }
        }
    }

    // MARK: - New fields: location_text and meeting_link

    func testRoundTrip_locationText() {
        let date = makeDate(2026, 6, 10, 14, 0)
        let note = MeetingNote(
            id: "LOC1", title: "Test",
            date: date,
            locationText: "Acme HQ · Room 4"
        )
        let rt = FrontmatterSerializer.parse(fileText: FrontmatterSerializer.render(note: note))
        XCTAssertEqual(rt.locationText, "Acme HQ · Room 4")
    }

    func testRoundTrip_meetingLink() {
        let date = makeDate(2026, 6, 10, 14, 0)
        let note = MeetingNote(
            id: "LINK1", title: "Test",
            date: date,
            meetingLink: "https://zoom.us/j/8421337"
        )
        let rt = FrontmatterSerializer.parse(fileText: FrontmatterSerializer.render(note: note))
        XCTAssertEqual(rt.meetingLink, "https://zoom.us/j/8421337")
    }

    func testRoundTrip_bothNewFields() {
        let date = makeDate(2026, 6, 10, 14, 0)
        let note = MeetingNote(
            id: "BOTH1", title: "Weekly Sync",
            date: date,
            locationText: "Café Nord",
            meetingLink: "https://meet.google.com/abc-defg-hij"
        )
        let rt = FrontmatterSerializer.parse(fileText: FrontmatterSerializer.render(note: note))
        XCTAssertEqual(rt.locationText, "Café Nord")
        XCTAssertEqual(rt.meetingLink, "https://meet.google.com/abc-defg-hij")
    }

    func testRoundTrip_nilLocationTextAndLink() {
        let date = makeDate(2026, 6, 10, 14, 0)
        let note = MeetingNote(id: "NIL1", title: "Test", date: date)
        let rt = FrontmatterSerializer.parse(fileText: FrontmatterSerializer.render(note: note))
        XCTAssertNil(rt.locationText)
        XCTAssertNil(rt.meetingLink)
    }

    func testRender_omitsLocationTextAndLinkWhenNil() {
        let date = makeDate(2026, 6, 10, 14, 0)
        let note = MeetingNote(id: "NIL2", title: "Test", date: date)
        let rendered = FrontmatterSerializer.render(note: note)
        XCTAssertFalse(rendered.contains("location_text"))
        XCTAssertFalse(rendered.contains("meeting_link"))
    }
}

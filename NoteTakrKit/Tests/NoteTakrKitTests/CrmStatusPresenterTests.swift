import XCTest
@testable import NoteTakrKit

final class CrmStatusPresenterTests: XCTestCase {
    func testBannerHiddenWhenCrmNotConnected() {
        let presenter = CrmStatusPresenter()

        XCTAssertNil(
            presenter.bannerText(
                meetingId: "meeting-a",
                crmConnected: false,
                unmatchedParticipants: [Participant(name: "Mystery Guest")]
            )
        )
    }

    func testBannerHiddenWhenAllParticipantsMatched() {
        let presenter = CrmStatusPresenter()

        XCTAssertNil(
            presenter.bannerText(
                meetingId: "meeting-a",
                crmConnected: true,
                unmatchedParticipants: []
            )
        )
    }

    func testBannerTextCountsUnmatchedParticipants() {
        let presenter = CrmStatusPresenter()

        XCTAssertEqual(
            presenter.bannerText(
                meetingId: "meeting-a",
                crmConnected: true,
                unmatchedParticipants: [
                    Participant(name: "Mystery Guest"),
                    Participant(name: "No Match", email: "no.match@example.test"),
                ]
            ),
            "2 participants not in CRM"
        )
        XCTAssertEqual(
            presenter.bannerText(
                meetingId: "meeting-b",
                crmConnected: true,
                unmatchedParticipants: [Participant(name: "Mystery Guest")]
            ),
            "1 participant not in CRM"
        )
    }

    func testDismissSilencesBannerForThatMeetingOnly() {
        var presenter = CrmStatusPresenter()

        presenter.dismiss(meetingId: "meeting-a")

        XCTAssertNil(
            presenter.bannerText(
                meetingId: "meeting-a",
                crmConnected: true,
                unmatchedParticipants: [Participant(name: "Mystery Guest")]
            )
        )
        XCTAssertEqual(
            presenter.bannerText(
                meetingId: "meeting-b",
                crmConnected: true,
                unmatchedParticipants: [Participant(name: "Mystery Guest")]
            ),
            "1 participant not in CRM"
        )
    }
}

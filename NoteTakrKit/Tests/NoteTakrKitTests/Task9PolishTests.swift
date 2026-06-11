import XCTest
@testable import NoteTakrKit

final class Task9PolishTests: XCTestCase {

    // MARK: - Theme spot-checks (Dark)

    func testDarkThemeBackgroundIsExpectedHex() {
        let t = Theme.dark
        // Neutralized: #0D0D0F = rgb(13, 13, 15) — no purple tint
        XCTAssertEqual(Int(t.background.r * 255), 13)
        XCTAssertEqual(Int(t.background.g * 255), 13)
        XCTAssertEqual(Int(t.background.b * 255), 15)
        XCTAssertEqual(t.background.a, 1.0)
    }

    func testDarkThemeAccentIsPurpleLight() {
        let t = Theme.dark
        // kit.css dark: --accent: #A78BFA = rgb(167, 139, 250)
        XCTAssertEqual(Int(round(t.accent.r * 255)), 167)
        XCTAssertEqual(Int(round(t.accent.g * 255)), 139)
        XCTAssertEqual(Int(round(t.accent.b * 255)), 250)
    }

    // MARK: - Theme spot-checks (Light)

    func testLightThemeBackgroundIsNeutralWhite() {
        let t = Theme.light
        // Neutralized: #F7F7F8 = rgb(247, 247, 248) — no warm paper tint
        XCTAssertEqual(Int(t.background.r * 255), 247)
        XCTAssertEqual(Int(t.background.g * 255), 247)
        XCTAssertEqual(Int(t.background.b * 255), 248)
        XCTAssertEqual(t.background.a, 1.0)
    }

    func testLightThemeAccentIsDarkerPurple() {
        let t = Theme.light
        // kit.css light: --accent: #8B5CF6 = rgb(139, 92, 246)
        XCTAssertEqual(Int(round(t.accent.r * 255)), 139)
        XCTAssertEqual(Int(round(t.accent.g * 255)), 92)
        XCTAssertEqual(Int(round(t.accent.b * 255)), 246)
    }

    func testLightThemePrimaryTextIsDark() {
        let t = Theme.light
        // kit.css light: --txt is dark near-black at 0.92 opacity
        XCTAssertLessThan(t.primaryText.r, 0.2)
        XCTAssertLessThan(t.primaryText.g, 0.2)
        XCTAssertLessThan(t.primaryText.b, 0.2)
    }

    // MARK: - Theme spot-checks (Glass)

    func testGlassThemeBackgroundIsSemiTransparent() {
        let t = Theme.glass
        // kit.css: glass background has alpha < 1.0 (it's a translucent overlay)
        XCTAssertLessThan(t.background.a, 1.0)
        XCTAssertGreaterThan(t.background.a, 0.0)
    }

    func testGlassThemePrimaryTextIsWhite() {
        let t = Theme.glass
        // Glass: text is white at 0.92 opacity
        XCTAssertEqual(t.primaryText.r, 1.0, accuracy: 0.01)
        XCTAssertEqual(t.primaryText.g, 1.0, accuracy: 0.01)
        XCTAssertEqual(t.primaryText.b, 1.0, accuracy: 0.01)
    }

    // MARK: - Shared design constants

    func testAccentPurpleMatchesKitCss() {
        // kit.css :root --accent-mid: #8B5CF6
        let p = DesignConstants.purple
        XCTAssertEqual(Int(round(p.r * 255)), 139)
        XCTAssertEqual(Int(round(p.g * 255)), 92)
        XCTAssertEqual(Int(round(p.b * 255)), 246)
    }

    func testPausedAmberMatchesKitCss() {
        // kit.css: --amber: #FF9F0A
        let a = DesignConstants.pauseAmber
        XCTAssertEqual(Int(round(a.r * 255)), 255)
        XCTAssertEqual(Int(round(a.g * 255)), 159)
        XCTAssertEqual(Int(round(a.b * 255)), 10)
    }

    func testRecRedMatchesKitCss() {
        // kit.css: --rec: #FF453A
        let r = DesignConstants.recRed
        XCTAssertEqual(Int(round(r.r * 255)), 255)
        XCTAssertEqual(Int(round(r.g * 255)), 69)
        XCTAssertEqual(Int(round(r.b * 255)), 58)
    }

    // MARK: - Raw markdown copy (source preservation)

    func testMarkdownParserPreservesMultilineSource() {
        let source = "- item 1\n- item 2\n\n> blockquote\n\n```swift\nlet x = 1\n```"
        let parsed = MarkdownBodyParser.parse(source)
        XCTAssertEqual(parsed.rawSource, source)
    }
}

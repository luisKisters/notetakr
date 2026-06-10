import XCTest
@testable import NoteTakrKit

final class ThemeTests: XCTestCase {

    // MARK: - colors(for:) returns the right set per appearance

    func testColorsForGlassMatchesStaticProperty() {
        XCTAssertEqual(Theme.colors(for: .glass), Theme.glass)
    }

    func testColorsForDarkMatchesStaticProperty() {
        XCTAssertEqual(Theme.colors(for: .dark), Theme.dark)
    }

    func testColorsForLightMatchesStaticProperty() {
        XCTAssertEqual(Theme.colors(for: .light), Theme.light)
    }

    // MARK: - Exhaustive coverage: every Appearance case has a non-default token set

    func testAllAppearanceCasesHandled() {
        for appearance in Appearance.allCases {
            let colors = Theme.colors(for: appearance)
            // Every token must have non-negative components — sanity guard
            XCTAssertGreaterThanOrEqual(colors.background.a, 0.0, "\(appearance) background alpha")
            XCTAssertGreaterThanOrEqual(colors.accent.r, 0.0, "\(appearance) accent r")
        }
    }

    // MARK: - Dark background is #151417

    func testDarkBackground() {
        let bg = Theme.dark.background
        XCTAssertEqual(bg, RGBA(red: 21, green: 20, blue: 23))
        XCTAssertEqual(bg.a, 1.0)
    }

    // MARK: - Light background is #FAF8F4 (warm paper)

    func testLightBackground() {
        let bg = Theme.light.background
        XCTAssertEqual(bg, RGBA(red: 250, green: 248, blue: 244))
        XCTAssertEqual(bg.a, 1.0)
    }

    // MARK: - Glass background is semi-transparent

    func testGlassBackgroundIsSemiTransparent() {
        let bg = Theme.glass.background
        XCTAssertGreaterThan(bg.a, 0.0)
        XCTAssertLessThan(bg.a, 1.0)
        XCTAssertEqual(bg, RGBA(red: 46, green: 44, blue: 54, alpha: 0.44))
    }

    // MARK: - Dark/light backgrounds are fully opaque

    func testDarkAndLightBackgroundsAreOpaque() {
        XCTAssertEqual(Theme.dark.background.a, 1.0)
        XCTAssertEqual(Theme.light.background.a, 1.0)
    }

    // MARK: - Accent colours: dark/glass use the light purple (#A78BFA), light uses the darker (#8B5CF6)

    func testDarkAccentIsLightPurple() {
        XCTAssertEqual(Theme.dark.accent, RGBA(red: 167, green: 139, blue: 250))
    }

    func testGlassAccentIsLightPurple() {
        XCTAssertEqual(Theme.glass.accent, RGBA(red: 167, green: 139, blue: 250))
    }

    func testLightAccentIsDarkerPurple() {
        XCTAssertEqual(Theme.light.accent, RGBA(red: 139, green: 92, blue: 246))
    }

    func testDarkAndLightAccentsDiffer() {
        XCTAssertNotEqual(Theme.dark.accent, Theme.light.accent)
    }

    // MARK: - Destructive colour is consistent across modes (#FF453A)

    func testDestructiveIsConsistentAcrossModes() {
        let expected = RGBA(red: 255, green: 69, blue: 58)
        XCTAssertEqual(Theme.glass.destructive, expected)
        XCTAssertEqual(Theme.dark.destructive, expected)
        XCTAssertEqual(Theme.light.destructive, expected)
    }

    // MARK: - Light mode uses dark text, glass/dark use white text

    func testLightPrimaryTextIsDark() {
        let txt = Theme.light.primaryText
        XCTAssertLessThan(txt.r, 0.5)
        XCTAssertLessThan(txt.g, 0.5)
        XCTAssertLessThan(txt.b, 0.5)
    }

    func testDarkPrimaryTextIsLight() {
        let txt = Theme.dark.primaryText
        XCTAssertGreaterThan(txt.r, 0.5)
    }

    func testGlassPrimaryTextIsLight() {
        let txt = Theme.glass.primaryText
        XCTAssertGreaterThan(txt.r, 0.5)
    }

    // MARK: - Hairline opacity matches mockup values

    func testDarkHairlineOpacity() {
        XCTAssertEqual(Theme.dark.hairline.a, 0.10, accuracy: 1e-9)
    }

    func testLightHairlineUsesBlackBase() {
        let h = Theme.light.hairline
        XCTAssertEqual(h.r, 0.0, accuracy: 1e-9)
        XCTAssertEqual(h.g, 0.0, accuracy: 1e-9)
        XCTAssertEqual(h.b, 0.0, accuracy: 1e-9)
        XCTAssertEqual(h.a, 0.10, accuracy: 1e-9)
    }

    // MARK: - Elevated fill: glass/dark are white-tinted, light is black-tinted

    func testGlassElevatedFillIsWhiteTinted() {
        let fill = Theme.glass.elevatedFill
        XCTAssertEqual(fill.r, 1.0, accuracy: 1e-9)
        XCTAssertEqual(fill.g, 1.0, accuracy: 1e-9)
        XCTAssertEqual(fill.b, 1.0, accuracy: 1e-9)
        XCTAssertLessThan(fill.a, 0.1)
    }

    func testLightElevatedFillIsBlackTinted() {
        let fill = Theme.light.elevatedFill
        XCTAssertEqual(fill.r, 0.0, accuracy: 1e-9)
        XCTAssertEqual(fill.g, 0.0, accuracy: 1e-9)
        XCTAssertEqual(fill.b, 0.0, accuracy: 1e-9)
        XCTAssertLessThan(fill.a, 0.1)
    }
}

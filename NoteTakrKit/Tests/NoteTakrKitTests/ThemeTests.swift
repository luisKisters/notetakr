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

    // MARK: - Exhaustive coverage

    func testAllAppearanceCasesHandled() {
        for appearance in Appearance.allCases {
            let colors = Theme.colors(for: appearance)
            XCTAssertGreaterThanOrEqual(colors.background.a, 0.0, "\(appearance) background alpha")
            XCTAssertGreaterThanOrEqual(colors.accent.r, 0.0, "\(appearance) accent r")
        }
    }

    // MARK: - Background values

    func testDarkBackground() {
        let bg = Theme.dark.background
        XCTAssertEqual(bg, RGBA(red: 21, green: 20, blue: 23))
        XCTAssertEqual(bg.a, 1.0)
    }

    func testLightBackground() {
        let bg = Theme.light.background
        XCTAssertEqual(bg, RGBA(red: 250, green: 248, blue: 244))
        XCTAssertEqual(bg.a, 1.0)
    }

    func testGlassBackgroundIsSemiTransparent() {
        let bg = Theme.glass.background
        XCTAssertGreaterThan(bg.a, 0.0)
        XCTAssertLessThan(bg.a, 1.0)
        XCTAssertEqual(bg, RGBA(red: 46, green: 44, blue: 54, alpha: 0.44))
    }

    func testDarkAndLightBackgroundsAreOpaque() {
        XCTAssertEqual(Theme.dark.background.a, 1.0)
        XCTAssertEqual(Theme.light.background.a, 1.0)
    }

    // MARK: - Accent colours

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

    // MARK: - Destructive colour (#FF453A — consistent)

    func testDestructiveIsConsistentAcrossModes() {
        let expected = RGBA(red: 255, green: 69, blue: 58)
        XCTAssertEqual(Theme.glass.destructive, expected)
        XCTAssertEqual(Theme.dark.destructive, expected)
        XCTAssertEqual(Theme.light.destructive, expected)
    }

    // MARK: - Text hierarchy

    func testLightPrimaryTextIsDark() {
        let txt = Theme.light.primaryText
        XCTAssertLessThan(txt.r, 0.5)
        XCTAssertLessThan(txt.g, 0.5)
        XCTAssertLessThan(txt.b, 0.5)
    }

    func testDarkPrimaryTextIsLight() {
        XCTAssertGreaterThan(Theme.dark.primaryText.r, 0.5)
    }

    func testGlassPrimaryTextIsLight() {
        XCTAssertGreaterThan(Theme.glass.primaryText.r, 0.5)
    }

    func testTertiaryTextIsLessOpaqueThanSecondary() {
        for appearance in Appearance.allCases {
            let c = Theme.colors(for: appearance)
            XCTAssertLessThan(c.tertiaryText.a, c.secondaryText.a,
                              "\(appearance): tertiary should be less opaque than secondary")
        }
    }

    func testLightTertiaryTextIs40PercentOpaque() {
        XCTAssertEqual(Theme.light.tertiaryText.a, 0.40, accuracy: 1e-9)
    }

    // MARK: - Hairline

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

    // MARK: - Elevated fill

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

    // MARK: - Hover fill (row/button hover background)

    func testHoverFillIsSemiTransparent() {
        for appearance in Appearance.allCases {
            let c = Theme.colors(for: appearance)
            XCTAssertGreaterThan(c.hoverFill.a, 0.0, "\(appearance) hoverFill")
            XCTAssertLessThan(c.hoverFill.a, 0.2, "\(appearance) hoverFill")
        }
    }

    // MARK: - Chip tokens

    func testChipFillHoverIsMoreOpaqueThanChipFill() {
        for appearance in Appearance.allCases {
            let c = Theme.colors(for: appearance)
            XCTAssertGreaterThan(c.chipFillHover.a, c.chipFill.a,
                                 "\(appearance): chipFillHover should be more opaque than chipFill")
        }
    }

    func testGlassChipFillMatches() {
        XCTAssertEqual(Theme.glass.chipFill.a, 0.055, accuracy: 1e-9)
    }

    func testLightChipFillIsBlackTinted() {
        let fill = Theme.light.chipFill
        XCTAssertEqual(fill.r, 0.0, accuracy: 1e-9)
        XCTAssertEqual(fill.a, 0.04, accuracy: 1e-9)
    }

    // MARK: - KBD pill tokens

    func testKbdBackgroundAndBorderExist() {
        for appearance in Appearance.allCases {
            let c = Theme.colors(for: appearance)
            XCTAssertGreaterThan(c.kbdBackground.a, 0.0, "\(appearance) kbdBg")
            XCTAssertGreaterThan(c.kbdBorder.a, 0.0, "\(appearance) kbdBorder")
        }
    }

    func testLightKbdIsBlackTinted() {
        XCTAssertEqual(Theme.light.kbdBackground.r, 0.0, accuracy: 1e-9)
        XCTAssertEqual(Theme.light.kbdBorder.r, 0.0, accuracy: 1e-9)
    }

    // MARK: - Avatar ring matches background hue

    func testDarkAvatarRingMatchesBackground() {
        XCTAssertEqual(Theme.dark.avatarRing, Theme.dark.background)
    }

    func testLightAvatarRingMatchesBackground() {
        XCTAssertEqual(Theme.light.avatarRing, Theme.light.background)
    }

    func testGlassAvatarRingIsNearBlack() {
        let ring = Theme.glass.avatarRing
        XCTAssertLessThan(ring.r, 0.1)
        XCTAssertLessThan(ring.g, 0.1)
        XCTAssertGreaterThan(ring.a, 0.8)
    }

    // MARK: - Traffic-light dot (dimmed state)

    func testTrafficLightDotIsSemiTransparent() {
        for appearance in Appearance.allCases {
            let c = Theme.colors(for: appearance)
            XCTAssertGreaterThan(c.trafficLightDot.a, 0.0, "\(appearance) trafficLightDot")
            XCTAssertLessThan(c.trafficLightDot.a, 1.0, "\(appearance) trafficLightDot")
        }
    }

    func testLightTrafficLightDotIsBlackTinted() {
        let dot = Theme.light.trafficLightDot
        XCTAssertEqual(dot.r, 0.0, accuracy: 1e-9)
        XCTAssertEqual(dot.g, 0.0, accuracy: 1e-9)
        XCTAssertEqual(dot.b, 0.0, accuracy: 1e-9)
    }

    // MARK: - Toggle-off color

    func testToggleOffIsMoreOpaqueThanHover() {
        for appearance in Appearance.allCases {
            let c = Theme.colors(for: appearance)
            XCTAssertGreaterThan(c.toggleOff.a, c.hoverFill.a,
                                 "\(appearance): toggleOff should be more prominent than hover")
        }
    }

    // MARK: - Field fill

    func testLightFieldFillIsMostlyOpaque() {
        XCTAssertGreaterThan(Theme.light.fieldFill.a, 0.5)
    }

    func testDarkFieldFillIsSubtle() {
        XCTAssertLessThan(Theme.dark.fieldFill.a, 0.15)
    }
}

// MARK: - DesignConstantsTests

final class DesignConstantsTests: XCTestCase {

    func testPurpleHex() {
        let p = DesignConstants.purple
        XCTAssertEqual(p, RGBA(red: 139, green: 92, blue: 246))
    }

    func testPurpleLightHex() {
        let p = DesignConstants.purpleLight
        XCTAssertEqual(p, RGBA(red: 167, green: 139, blue: 250))
    }

    func testRecRedHex() {
        let r = DesignConstants.recRed
        XCTAssertEqual(r, RGBA(red: 255, green: 69, blue: 58))
    }

    func testRecRedMatchesDestructive() {
        for appearance in Appearance.allCases {
            XCTAssertEqual(DesignConstants.recRed, Theme.colors(for: appearance).destructive,
                           "\(appearance): recRed should match destructive token")
        }
    }

    func testWindowDimensions() {
        XCTAssertEqual(DesignConstants.windowWidth, 420)
        XCTAssertEqual(DesignConstants.windowHeight, 620)
    }

    func testWindowRadius() {
        XCTAssertEqual(DesignConstants.windowRadius, 16)
    }

    func testChipRadius() {
        XCTAssertEqual(DesignConstants.chipRadius, 7)
    }

    func testPropsRadius() {
        XCTAssertEqual(DesignConstants.propsRadius, 10)
    }

    func testPurpleAndPurpleLightDiffer() {
        XCTAssertNotEqual(DesignConstants.purple, DesignConstants.purpleLight)
    }

    func testStatusGreenAndPauseAmberAreDifferentHues() {
        XCTAssertNotEqual(DesignConstants.statusGreen, DesignConstants.pauseAmber)
    }
}

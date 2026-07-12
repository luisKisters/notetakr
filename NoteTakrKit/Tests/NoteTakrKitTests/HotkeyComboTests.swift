import XCTest
@testable import NoteTakrKit

final class HotkeyComboTests: XCTestCase {

    // MARK: - Round-trip: default hotkey

    func testDefaultHotkeyRoundTrip() throws {
        let combo = try HotkeyCombo.parse("⌃⌥⌘N")
        XCTAssertEqual(combo.displayString, "⌃⌥⌘N")
        XCTAssertTrue(combo.modifiers.contains(.control))
        XCTAssertTrue(combo.modifiers.contains(.option))
        XCTAssertTrue(combo.modifiers.contains(.command))
        XCTAssertFalse(combo.modifiers.contains(.shift))
        XCTAssertEqual(combo.key, "N")
    }

    // MARK: - Round-trip for all individual modifiers

    func testSingleControlModifier() throws {
        let combo = try HotkeyCombo.parse("⌃A")
        XCTAssertEqual(combo.displayString, "⌃A")
        XCTAssertEqual(combo.modifiers, .control)
    }

    func testSingleOptionModifier() throws {
        let combo = try HotkeyCombo.parse("⌥B")
        XCTAssertEqual(combo.displayString, "⌥B")
        XCTAssertEqual(combo.modifiers, .option)
    }

    func testSingleShiftModifier() throws {
        let combo = try HotkeyCombo.parse("⇧C")
        XCTAssertEqual(combo.displayString, "⇧C")
        XCTAssertEqual(combo.modifiers, .shift)
    }

    func testSingleCommandModifier() throws {
        let combo = try HotkeyCombo.parse("⌘D")
        XCTAssertEqual(combo.displayString, "⌘D")
        XCTAssertEqual(combo.modifiers, .command)
    }

    func testAllFourModifiers() throws {
        let combo = try HotkeyCombo.parse("⌃⌥⇧⌘Z")
        XCTAssertEqual(combo.displayString, "⌃⌥⇧⌘Z")
        XCTAssertEqual(combo.modifiers, [.control, .option, .shift, .command])
    }

    func testControlCommandCombo() throws {
        let combo = try HotkeyCombo.parse("⌃⌘P")
        XCTAssertEqual(combo.displayString, "⌃⌘P")
    }

    func testOptionCommandCombo() throws {
        let combo = try HotkeyCombo.parse("⌥⌘K")
        XCTAssertEqual(combo.displayString, "⌥⌘K")
    }

    // MARK: - Digit keys

    func testDigitKey() throws {
        let combo = try HotkeyCombo.parse("⌘5")
        XCTAssertEqual(combo.displayString, "⌘5")
        XCTAssertEqual(combo.key, "5")
    }

    func testDigitKeyZero() throws {
        let combo = try HotkeyCombo.parse("⌃0")
        XCTAssertEqual(combo.key, "0")
    }

    // MARK: - Lowercase normalisation

    func testLowercaseKeyNormalised() throws {
        let combo = try HotkeyCombo.parse("⌘n")
        XCTAssertEqual(combo.key, "N")
        XCTAssertEqual(combo.displayString, "⌘N")
    }

    func testLowercaseKeyAllModifiers() throws {
        let combo = try HotkeyCombo.parse("⌃⌥⌘p")
        XCTAssertEqual(combo.key, "P")
        XCTAssertEqual(combo.displayString, "⌃⌥⌘P")
    }

    // MARK: - Non-canonical modifier order is canonicalised

    func testReverseModifierOrderCanonicalisedInOutput() throws {
        // Input: ⌘⌃N (command before control) → output must use canonical ⌃⌘N order
        let combo1 = try HotkeyCombo.parse("⌘⌃N")
        let combo2 = try HotkeyCombo.parse("⌃⌘N")
        XCTAssertEqual(combo1, combo2)
        XCTAssertEqual(combo1.displayString, combo2.displayString)
        XCTAssertEqual(combo1.displayString, "⌃⌘N")
    }

    // MARK: - Invalid inputs rejected

    func testNoModifierReject() {
        XCTAssertThrowsError(try HotkeyCombo.parse("N")) { error in
            XCTAssertEqual(error as? HotkeyCombo.ParseError, .noModifier)
        }
    }

    func testModifierOnlyNoKeyReject() {
        XCTAssertThrowsError(try HotkeyCombo.parse("⌘")) { error in
            // No key character after modifier → unknownKey("")
            if case let HotkeyCombo.ParseError.unknownKey(k) = error as! HotkeyCombo.ParseError {
                XCTAssertEqual(k, "")
            } else {
                XCTFail("Expected unknownKey, got \(error)")
            }
        }
    }

    func testUnknownKeyChessKnight() {
        XCTAssertThrowsError(try HotkeyCombo.parse("⌃⌥⌘♞")) { error in
            if case let HotkeyCombo.ParseError.unknownKey(k) = error as! HotkeyCombo.ParseError {
                XCTAssertEqual(k, "♞")
            } else {
                XCTFail("Expected unknownKey, got \(error)")
            }
        }
    }

    func testUnknownKeySymbol() {
        XCTAssertThrowsError(try HotkeyCombo.parse("⌘!")) { error in
            XCTAssertEqual(error as? HotkeyCombo.ParseError, .unknownKey("!"))
        }
    }

    func testEmptyStringReject() {
        XCTAssertThrowsError(try HotkeyCombo.parse("")) { error in
            // empty → unknownKey("")
            XCTAssertEqual(error as? HotkeyCombo.ParseError, .unknownKey(""))
        }
    }

    // MARK: - init(modifiers:key:) rejects directly

    func testInitNoModifierThrows() {
        XCTAssertThrowsError(try HotkeyCombo(modifiers: [], key: "N")) { error in
            XCTAssertEqual(error as? HotkeyCombo.ParseError, .noModifier)
        }
    }

    func testInitUnknownKeyThrows() {
        XCTAssertThrowsError(try HotkeyCombo(modifiers: .command, key: "♞")) { error in
            XCTAssertEqual(error as? HotkeyCombo.ParseError, .unknownKey("♞"))
        }
    }

    // MARK: - Codable round-trip

    func testCodableRoundTrip() throws {
        let original = try HotkeyCombo.parse("⌃⌥⌘N")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HotkeyCombo.self, from: data)
        XCTAssertEqual(original, decoded)
        // Wire format is the display string
        let string = try JSONDecoder().decode(String.self, from: data)
        XCTAssertEqual(string, "⌃⌥⌘N")
    }

    func testCodableRoundTripAllModifiers() throws {
        let original = try HotkeyCombo.parse("⌃⌥⇧⌘Z")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HotkeyCombo.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func testCodableDecodesFromDisplayString() throws {
        let data = try JSONEncoder().encode("⌘K")
        let combo = try JSONDecoder().decode(HotkeyCombo.self, from: data)
        XCTAssertEqual(combo.modifiers, .command)
        XCTAssertEqual(combo.key, "K")
    }

    func testCodableDecodingInvalidStringThrows() {
        let data = try! JSONEncoder().encode("N")  // no modifier
        XCTAssertThrowsError(try JSONDecoder().decode(HotkeyCombo.self, from: data))
    }

    // MARK: - AppSettingsStore round-trip with HotkeyCombo

    func testAppSettingsStoreHotkeyRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("NoteTakrKitTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let store = AppSettingsStore(root: dir)
        store.hotkey = try HotkeyCombo.parse("⌃⌥⌘N")
        store.recordingHotkey = try HotkeyCombo.parse("⌃⌥⌘R")
        XCTAssertEqual(store.hotkey.displayString, "⌃⌥⌘N")
        XCTAssertEqual(store.recordingHotkey.displayString, "⌃⌥⌘R")

        let store2 = AppSettingsStore(root: dir)
        XCTAssertEqual(store2.hotkey, try HotkeyCombo.parse("⌃⌥⌘N"))
        XCTAssertEqual(store2.recordingHotkey, try HotkeyCombo.parse("⌃⌥⌘R"))
    }
}

import Foundation

// MARK: - HotkeyCombo

/// A validated modifier + key combo (e.g. ⌃⌥⌘N). Codable as its display string.
public struct HotkeyCombo: Equatable {

    // MARK: - Errors

    public enum ParseError: Error, Equatable {
        case noModifier
        case unknownKey(String)
    }

    // MARK: - Modifiers

    public struct Modifiers: OptionSet, Equatable, Hashable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let control = Modifiers(rawValue: 1 << 0)  // ⌃
        public static let option  = Modifiers(rawValue: 1 << 1)  // ⌥
        public static let shift   = Modifiers(rawValue: 1 << 2)  // ⇧
        public static let command = Modifiers(rawValue: 1 << 3)  // ⌘
    }

    // MARK: - Properties

    public let modifiers: Modifiers
    public let key: Character   // always uppercase A–Z or 0–9

    // MARK: - Init

    /// Creates a validated combo. Throws `noModifier` if no modifiers given, or
    /// `unknownKey` if the key is not A–Z / 0–9. Normalises key to uppercase.
    public init(modifiers: Modifiers, key: Character) throws {
        guard !modifiers.isEmpty else { throw ParseError.noModifier }
        let upper = Character(String(key).uppercased())
        guard Self.knownKeys.contains(upper) else {
            throw ParseError.unknownKey(String(key))
        }
        self.modifiers = modifiers
        self.key = upper
    }

    // MARK: - Display

    /// Canonical representation: ⌃⌥⇧⌘ then key (standard macOS modifier order).
    public var displayString: String {
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option)  { s += "⌥" }
        if modifiers.contains(.shift)   { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        s += String(key)
        return s
    }

    // MARK: - Parsing

    /// Parses a display string like "⌃⌥⌘N". Accepts any modifier order; output is
    /// always canonical. Throws `noModifier` or `unknownKey` on invalid input.
    public static func parse(_ string: String) throws -> HotkeyCombo {
        let modMap: [Character: Modifiers] = [
            "⌃": .control, "⌥": .option, "⇧": .shift, "⌘": .command
        ]
        var remaining = Substring(string)
        var mods = Modifiers()

        while let first = remaining.first, let mod = modMap[first] {
            mods.insert(mod)
            remaining = remaining.dropFirst()
        }

        guard remaining.count == 1 else {
            throw ParseError.unknownKey(String(remaining))
        }

        return try HotkeyCombo(modifiers: mods, key: remaining.first!)
    }

    // MARK: - Known keys

    private static let knownKeys: Set<Character> = {
        var s = Set<Character>()
        "ABCDEFGHIJKLMNOPQRSTUVWXYZ".forEach { s.insert($0) }
        "0123456789".forEach { s.insert($0) }
        return s
    }()
}

// MARK: - Codable (wire format is the display string)

extension HotkeyCombo: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        self = try HotkeyCombo.parse(string)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(displayString)
    }
}

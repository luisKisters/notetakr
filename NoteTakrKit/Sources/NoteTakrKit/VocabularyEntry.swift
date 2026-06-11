import Foundation

public struct VocabularyEntry: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var phrase: String
    public var aliases: [String]
    public var isEnabled: Bool
    public var boostingWeight: Double

    public init(
        id: UUID = UUID(),
        phrase: String,
        aliases: [String] = [],
        isEnabled: Bool = true,
        boostingWeight: Double = 1.0
    ) {
        self.id = id
        self.phrase = phrase
        self.aliases = aliases
        self.isEnabled = isEnabled
        self.boostingWeight = boostingWeight
    }
}

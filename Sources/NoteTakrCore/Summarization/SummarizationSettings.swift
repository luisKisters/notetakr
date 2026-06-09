import Foundation

/// A selectable model: a friendly display name paired with the OpenRouter model
/// slug actually sent on the wire. The slug is editable in the UI so a wrong
/// default can be corrected without a code change.
public struct SummarizationModelPreset: Codable, Equatable, Sendable, Identifiable {
    public var displayName: String
    public var slug: String

    public var id: String { displayName }

    public init(displayName: String, slug: String) {
        self.displayName = displayName
        self.slug = slug
    }
}

public struct SummarizationSettings: Codable, Equatable, Sendable {
    public var selectedModelSlug: String
    public var activeTemplateID: UUID?
    public var autoSummarize: Bool

    public init(
        selectedModelSlug: String = SummarizationSettings.presets[0].slug,
        activeTemplateID: UUID? = nil,
        autoSummarize: Bool = true
    ) {
        self.selectedModelSlug = selectedModelSlug
        self.activeTemplateID = activeTemplateID
        self.autoSummarize = autoSummarize
    }

    // Decode defensively so a settings file written by an older build (or with
    // fields absent) still loads.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        selectedModelSlug = (try? c.decodeIfPresent(String.self, forKey: .selectedModelSlug))
            .flatMap { $0 } ?? SummarizationSettings.presets[0].slug
        activeTemplateID = try? c.decodeIfPresent(UUID.self, forKey: .activeTemplateID)
        autoSummarize = (try? c.decodeIfPresent(Bool.self, forKey: .autoSummarize)).flatMap { $0 } ?? true
    }

    enum CodingKeys: String, CodingKey {
        case selectedModelSlug, activeTemplateID, autoSummarize
    }

    /// Best-guess model presets. The slugs are editable in Settings.
    public static let presets: [SummarizationModelPreset] = [
        SummarizationModelPreset(displayName: "Kimi K2.6", slug: "moonshotai/kimi-k2"),
        SummarizationModelPreset(displayName: "Opus 4.7", slug: "anthropic/claude-opus-4.7"),
    ]

    public static let `default` = SummarizationSettings()
}

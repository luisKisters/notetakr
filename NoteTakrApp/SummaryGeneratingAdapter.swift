import Foundation
import NoteTakrCore
import NoteTakrKit

final class SummaryGeneratingAdapter: SummaryGenerating, @unchecked Sendable {
    private let sessionStore: SessionStore
    private let summarizationService: SummarizationService
    private let settingsStore: SummarizationSettingsStore
    private let templateStore: SummaryTemplateStore
    private let keychainStore: KeychainStore
    private let shouldUseCloudSummary: (String) async -> Bool
    private let cloudGenerator: ((String) async throws -> String)?

    init(
        sessionStore: SessionStore,
        summarizationService: SummarizationService = SummarizationService(),
        settingsStore: SummarizationSettingsStore,
        templateStore: SummaryTemplateStore,
        keychainStore: KeychainStore,
        shouldUseCloudSummary: @escaping (String) async -> Bool = { _ in false },
        cloudGenerator: ((String) async throws -> String)? = nil
    ) {
        self.sessionStore = sessionStore
        self.summarizationService = summarizationService
        self.settingsStore = settingsStore
        self.templateStore = templateStore
        self.keychainStore = keychainStore
        self.shouldUseCloudSummary = shouldUseCloudSummary
        self.cloudGenerator = cloudGenerator
    }

    func generate(for noteID: String) async throws -> String {
        if await shouldUseCloudSummary(noteID), let cloudGenerator {
            return try await cloudGenerator(noteID)
        }

        guard let uuid = UUID(uuidString: noteID) else {
            throw AdapterError.invalidNoteID
        }
        guard let session = try sessionStore.load(id: uuid) else {
            throw AdapterError.sessionNotFound
        }
        guard let apiKey = keychainStore.read(), !apiKey.isEmpty else {
            throw OpenRouterError.missingAPIKey
        }
        let settings = settingsStore.load()
        let templates = templateStore.load()
        let template = templates.first(where: { $0.id == settings.activeTemplateID }) ?? templates.first
        guard let template else {
            throw AdapterError.noTemplate
        }
        return try await summarizationService.summarize(
            session: session,
            template: template,
            modelSlug: settings.selectedModelSlug,
            apiKey: apiKey
        )
    }

    enum AdapterError: Error, LocalizedError {
        case invalidNoteID
        case sessionNotFound
        case noTemplate

        var errorDescription: String? {
            switch self {
            case .invalidNoteID: return "Invalid note ID"
            case .sessionNotFound: return "Session not found"
            case .noTemplate: return "No summary template configured"
            }
        }
    }
}

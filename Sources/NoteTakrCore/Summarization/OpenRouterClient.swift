import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct OpenRouterMessage: Codable, Equatable, Sendable {
    public var role: String
    public var content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

public enum OpenRouterError: Error, Equatable, Sendable {
    case missingAPIKey
    case unauthorized          // 401 — bad/empty key
    case paymentRequired       // 402 — out of credits
    case rateLimited           // 429
    case server(Int)           // 5xx
    case http(Int)             // other non-2xx
    case invalidResponse       // unexpected/empty body
    case transport(String)     // URLSession failure
}

/// Seam over `URLSession` so the request-building logic can be unit-tested
/// without a live network call.
public protocol HTTPDataFetching: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPDataFetching {}

/// Minimal OpenRouter chat-completions client. Foundation-only so it lives in
/// Core and stays testable.
public final class OpenRouterClient: @unchecked Sendable {
    public static let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!

    private let session: any HTTPDataFetching

    public init(session: any HTTPDataFetching = URLSession.shared) {
        self.session = session
    }

    /// Sends a chat completion and returns the assistant's message text.
    public func complete(
        apiKey: String,
        model: String,
        messages: [OpenRouterMessage],
        temperature: Double = 0.3,
        maxTokens: Int = 1500
    ) async throws -> String {
        let request = try Self.buildRequest(
            apiKey: apiKey, model: model, messages: messages,
            temperature: temperature, maxTokens: maxTokens
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw OpenRouterError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw OpenRouterError.invalidResponse
        }
        switch http.statusCode {
        case 200..<300:
            break
        case 401:
            throw OpenRouterError.unauthorized
        case 402:
            throw OpenRouterError.paymentRequired
        case 429:
            throw OpenRouterError.rateLimited
        case 500...599:
            throw OpenRouterError.server(http.statusCode)
        default:
            throw OpenRouterError.http(http.statusCode)
        }

        guard let decoded = try? JSONDecoder().decode(OpenRouterResponse.self, from: data),
              let content = decoded.choices.first?.message.content,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw OpenRouterError.invalidResponse
        }
        return content
    }

    /// Builds the signed POST request. Exposed for unit testing the request shape.
    public static func buildRequest(
        apiKey: String,
        model: String,
        messages: [OpenRouterMessage],
        temperature: Double,
        maxTokens: Int
    ) throws -> URLRequest {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OpenRouterError.missingAPIKey
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Optional attribution headers recommended by OpenRouter.
        request.setValue("https://notetakr.app", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("NoteTakr", forHTTPHeaderField: "X-Title")

        let body = OpenRouterRequestBody(
            model: model, messages: messages, temperature: temperature, maxTokens: maxTokens
        )
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }
}

// MARK: - Wire types

struct OpenRouterRequestBody: Encodable {
    let model: String
    let messages: [OpenRouterMessage]
    let temperature: Double
    let maxTokens: Int

    enum CodingKeys: String, CodingKey {
        case model, messages, temperature
        case maxTokens = "max_tokens"
    }
}

struct OpenRouterResponse: Decodable {
    struct Choice: Decodable {
        let message: OpenRouterMessage
    }
    let choices: [Choice]
}

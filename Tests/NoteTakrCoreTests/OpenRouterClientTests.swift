import XCTest
@testable import NoteTakrCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class OpenRouterClientTests: XCTestCase {

    // MARK: - Request building

    func testBuildRequestSetsAuthorizationAndJSONBody() throws {
        let request = try OpenRouterClient.buildRequest(
            apiKey: "sk-test-123",
            model: "moonshotai/kimi-k2",
            messages: [
                OpenRouterMessage(role: "system", content: "Summarize."),
                OpenRouterMessage(role: "user", content: "Hello world"),
            ],
            temperature: 0.3,
            maxTokens: 800
        )

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url, OpenRouterClient.endpoint)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test-123")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, "moonshotai/kimi-k2")
        XCTAssertEqual(json["max_tokens"] as? Int, 800)
        XCTAssertEqual(json["temperature"] as? Double, 0.3)
        let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0]["role"] as? String, "system")
        XCTAssertEqual(messages[0]["content"] as? String, "Summarize.")
        XCTAssertEqual(messages[1]["role"] as? String, "user")
    }

    func testBuildRequestThrowsOnEmptyKey() {
        XCTAssertThrowsError(
            try OpenRouterClient.buildRequest(
                apiKey: "   ", model: "m", messages: [], temperature: 0.3, maxTokens: 100
            )
        ) { error in
            XCTAssertEqual(error as? OpenRouterError, .missingAPIKey)
        }
    }

    // MARK: - Response handling

    func testCompleteDecodesAssistantContent() async throws {
        let json = """
        {
          "id": "gen-1",
          "choices": [
            { "message": { "role": "assistant", "content": "Here is your summary." } }
          ]
        }
        """
        let session = StubFetcher(statusCode: 200, body: Data(json.utf8))
        let client = OpenRouterClient(session: session)

        let result = try await client.complete(
            apiKey: "sk-test", model: "m",
            messages: [OpenRouterMessage(role: "user", content: "hi")]
        )
        XCTAssertEqual(result, "Here is your summary.")
        XCTAssertEqual(session.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
    }

    func testCompleteMapsStatusCodesToErrors() async {
        await assertError(statusCode: 401, expected: .unauthorized)
        await assertError(statusCode: 402, expected: .paymentRequired)
        await assertError(statusCode: 429, expected: .rateLimited)
        await assertError(statusCode: 503, expected: .server(503))
        await assertError(statusCode: 418, expected: .http(418))
    }

    private func assertError(statusCode: Int, expected: OpenRouterError) async {
        let session = StubFetcher(statusCode: statusCode, body: Data("{}".utf8))
        let client = OpenRouterClient(session: session)
        do {
            _ = try await client.complete(
                apiKey: "sk-test", model: "m",
                messages: [OpenRouterMessage(role: "user", content: "hi")]
            )
            XCTFail("Expected error for status \(statusCode)")
        } catch let error as OpenRouterError {
            XCTAssertEqual(error, expected)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
}

private final class StubFetcher: HTTPDataFetching, @unchecked Sendable {
    let statusCode: Int
    let body: Data
    private(set) var lastRequest: URLRequest?

    init(statusCode: Int, body: Data) {
        self.statusCode = statusCode
        self.body = body
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lastRequest = request
        let response = HTTPURLResponse(
            url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: nil
        )!
        return (body, response)
    }
}

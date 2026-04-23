import Foundation
import XCTest
@testable import Ledger

final class ClaudeClientGenerateTextTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    func testGenerateTextBuildsNonStreamingMessagesRequest() async throws {
        let body = """
        {
          "content": [
            { "type": "text", "text": "Snapshot body." }
          ]
        }
        """
        MockURLProtocol.enqueue(
            .init(
                statusCode: 200,
                headers: ["Content-Type": "application/json"],
                body: Data(body.utf8)
            )
        )

        let client = ClaudeClient(session: MockURLProtocol.makeSession())
        let text = try await client.generateText(
            systemPrompt: "System prompt",
            userPrompt: "{\"foo\":\"bar\"}",
            maxTokens: 321
        )

        XCTAssertEqual(text, "Snapshot body.")

        let request = try XCTUnwrap(MockURLProtocol.capturedRequests.first?.request)
        XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        XCTAssertEqual(request.value(forHTTPHeaderField: "content-type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), Secrets.anthropicAPIKey)

        let data = try XCTUnwrap(MockURLProtocol.capturedRequests.first?.body)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, ClaudeClient.model)
        XCTAssertEqual(json["stream"] as? Bool, false)
        XCTAssertEqual(json["max_tokens"] as? Int, 321)
        XCTAssertEqual(json["system"] as? String, "System prompt")
        XCTAssertEqual((json["tools"] as? [Any])?.count, 0)
        XCTAssertNil(json["thinking"])
        XCTAssertNil(json["output_config"])

        let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages.first?["role"] as? String, "user")

        let content = try XCTUnwrap(messages.first?["content"] as? [[String: Any]])
        XCTAssertEqual(content.first?["type"] as? String, "text")
        XCTAssertEqual(content.first?["text"] as? String, "{\"foo\":\"bar\"}")
    }

    func testGenerateTextThrowsAPIErrorForNonSuccessResponse() async {
        let body = #"{"error":{"message":"Rate limited."}}"#
        MockURLProtocol.enqueue(
            .init(
                statusCode: 429,
                headers: ["Content-Type": "application/json"],
                body: Data(body.utf8)
            )
        )

        let client = ClaudeClient(session: MockURLProtocol.makeSession())

        do {
            _ = try await client.generateText(
                systemPrompt: "System prompt",
                userPrompt: "Body",
                maxTokens: 64
            )
            XCTFail("Expected generateText to throw.")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Rate limited.")
        }
    }

    func testGenerateTextThrowsInvalidResponseWhenNoTextIsPresent() async {
        let body = #"{"content":[{"type":"tool_use","id":"tool-1","name":"noop","input":{}}]}"#
        MockURLProtocol.enqueue(
            .init(
                statusCode: 200,
                headers: ["Content-Type": "application/json"],
                body: Data(body.utf8)
            )
        )

        let client = ClaudeClient(session: MockURLProtocol.makeSession())

        do {
            _ = try await client.generateText(
                systemPrompt: "System prompt",
                userPrompt: "Body",
                maxTokens: 64
            )
            XCTFail("Expected generateText to throw.")
        } catch {
            XCTAssertEqual(error.localizedDescription, ClaudeClientError.invalidResponse.localizedDescription)
        }
    }

    func testGenerateTextThrowsOnMalformedJSONResponse() async {
        MockURLProtocol.enqueue(
            .init(
                statusCode: 200,
                headers: ["Content-Type": "application/json"],
                body: Data("{".utf8)
            )
        )

        let client = ClaudeClient(session: MockURLProtocol.makeSession())

        do {
            _ = try await client.generateText(
                systemPrompt: "System prompt",
                userPrompt: "Body",
                maxTokens: 64
            )
            XCTFail("Expected generateText to throw.")
        } catch {
            XCTAssertFalse((error as NSError).localizedDescription.isEmpty)
        }
    }
}

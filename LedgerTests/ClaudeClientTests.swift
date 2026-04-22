import Foundation
import XCTest
@testable import Ledger

final class ClaudeClientTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    func testThrowsAPIErrorForNonSuccessResponse() async {
        let body = #"{"error":{"type":"invalid_request_error","message":"Bad request"}}"#
        MockURLProtocol.enqueue(
            .init(
                statusCode: 400,
                headers: ["Content-Type": "application/json"],
                body: Data(body.utf8)
            )
        )

        let client = ClaudeClient(session: MockURLProtocol.makeSession())
        let stream = await client.streamMessage(
            messages: [Message(role: .user, content: "Hi", timestamp: Date())],
            profile: "No saved profile yet.",
            todayLog: nil,
            tools: CoachTools.all
        )

        do {
            for try await _ in stream {}
            XCTFail("Expected the stream to throw.")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Bad request")
        }
    }

    func testContinuesAfterToolResultAndSendsFollowUpRequest() async throws {
        MockURLProtocol.enqueue(
            .init(
                statusCode: 200,
                headers: ["Content-Type": "text/event-stream"],
                body: Data(firstTurnSSE.utf8)
            )
        )
        MockURLProtocol.enqueue(
            .init(
                statusCode: 200,
                headers: ["Content-Type": "text/event-stream"],
                body: Data(secondTurnSSE.utf8)
            )
        )

        let client = ClaudeClient(session: MockURLProtocol.makeSession())
        let stream = await client.streamMessage(
            messages: [Message(role: .user, content: "had chicken", timestamp: Date())],
            profile: "No saved profile yet.",
            todayLog: nil,
            tools: CoachTools.all
        )

        var observedToolNames: [String] = []
        var observedText = ""
        var sawMessageStop = false

        for try await event in stream {
            switch event {
            case .toolUseStart(let id, let name):
                observedToolNames.append(name)
                XCTAssertEqual(id, "tool-1")
            case .toolUseEnd(let id):
                await client.completeToolUse(id: id, content: "Meal logged.", isError: false)
            case .textDelta(let delta):
                observedText += delta
            case .messageStop:
                sawMessageStop = true
            case .toolUseDelta:
                break
            }
        }

        XCTAssertEqual(observedToolNames, ["update_meal_log"])
        XCTAssertEqual(observedText, "Done.")
        XCTAssertTrue(sawMessageStop)
        XCTAssertEqual(MockURLProtocol.capturedRequests.count, 2)

        let secondBody = try XCTUnwrap(MockURLProtocol.capturedRequests.last?.body)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: secondBody) as? [String: Any]
        )
        let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
        let finalUserMessage = try XCTUnwrap(messages.last)
        let contentBlocks = try XCTUnwrap(finalUserMessage["content"] as? [[String: Any]])
        let toolResultBlock = try XCTUnwrap(
            contentBlocks.first(where: { ($0["type"] as? String) == "tool_result" })
        )

        XCTAssertEqual(toolResultBlock["tool_use_id"] as? String, "tool-1")
        XCTAssertEqual(toolResultBlock["content"] as? String, "Meal logged.")
    }

    private var firstTurnSSE: String {
        [
            #"event: message_start"#,
            #"data: {"type":"message_start"}"#,
            #"event: content_block_start"#,
            #"data: {"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"tool-1","name":"update_meal_log","input":{}}}"#,
            #"event: content_block_delta"#,
            #"data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\"description\":\"Chicken\""}} "#,
            #"event: content_block_delta"#,
            #"data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":",\"estimated_calories\":300,\"estimated_protein_grams\":50}"}}"#,
            #"event: content_block_stop"#,
            #"data: {"type":"content_block_stop","index":0}"#,
            #"event: message_delta"#,
            #"data: {"type":"message_delta","delta":{"stop_reason":"tool_use"}}"#,
            #"event: message_stop"#,
            #"data: {"type":"message_stop"}"#
        ].joined(separator: "\n")
    }

    private var secondTurnSSE: String {
        [
            #"event: message_start"#,
            #"data: {"type":"message_start"}"#,
            #"event: content_block_start"#,
            #"data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#,
            #"event: content_block_delta"#,
            #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Done."}}"#,
            #"event: content_block_stop"#,
            #"data: {"type":"content_block_stop","index":0}"#,
            #"event: message_delta"#,
            #"data: {"type":"message_delta","delta":{"stop_reason":"end_turn"}}"#,
            #"event: message_stop"#,
            #"data: {"type":"message_stop"}"#
        ].joined(separator: "\n")
    }
}

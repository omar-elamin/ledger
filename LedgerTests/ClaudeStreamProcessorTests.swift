import XCTest
@testable import Ledger

final class ClaudeStreamProcessorTests: XCTestCase {
    func testParsesTextEventsWithoutBlankSeparators() throws {
        var processor = ClaudeStreamProcessor()
        var emittedEvents: [StreamEvent] = []

        let lines = [
            #"event: message_start"#,
            #"data: {"type":"message_start"}"#,
            #"event: content_block_start"#,
            #"data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#,
            #"event: content_block_delta"#,
            #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hi"}}"#,
            #"event: content_block_delta"#,
            #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":" there"}}"#,
            #"event: content_block_stop"#,
            #"data: {"type":"content_block_stop","index":0}"#,
            #"event: message_delta"#,
            #"data: {"type":"message_delta","delta":{"stop_reason":"end_turn"}}"#,
            #"event: message_stop"#,
            #"data: {"type":"message_stop"}"#
        ]

        for line in lines {
            emittedEvents.append(contentsOf: try processor.ingest(line: line))
        }

        let processedTurn = try processor.finish()
        emittedEvents.append(contentsOf: processedTurn.emittedEvents)

        XCTAssertEqual(emittedEvents, [
            .textDelta("Hi"),
            .textDelta(" there")
        ])
        XCTAssertEqual(processedTurn.streamedTurn.stopReason, "end_turn")
        XCTAssertEqual(processedTurn.streamedTurn.toolUses.count, 0)
    }

    func testParsesToolUseEventsAndStopReason() throws {
        var processor = ClaudeStreamProcessor()
        var emittedEvents: [StreamEvent] = []

        let lines = [
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
        ]

        for line in lines {
            emittedEvents.append(contentsOf: try processor.ingest(line: line))
        }

        let processedTurn = try processor.finish()
        emittedEvents.append(contentsOf: processedTurn.emittedEvents)

        XCTAssertEqual(emittedEvents, [
            .toolUseStart(id: "tool-1", name: "update_meal_log"),
            .toolUseDelta(id: "tool-1", partialJSON: #"{"description":"Chicken""#),
            .toolUseDelta(id: "tool-1", partialJSON: #","estimated_calories":300,"estimated_protein_grams":50}"#),
            .toolUseEnd(id: "tool-1")
        ])
        XCTAssertEqual(processedTurn.streamedTurn.stopReason, "tool_use")
        XCTAssertEqual(processedTurn.streamedTurn.toolUses.map(\.name), ["update_meal_log"])
    }

    func testPreservesThinkingBlockBeforeToolUseWithoutEmittingThinkingEvents() throws {
        var processor = ClaudeStreamProcessor()
        var emittedEvents: [StreamEvent] = []

        let lines = [
            #"event: content_block_start"#,
            #"data: {"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":""}}"#,
            #"event: content_block_delta"#,
            #"data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"Need to log the meal before replying."}}"#,
            #"event: content_block_delta"#,
            #"data: {"type":"content_block_delta","index":0,"delta":{"type":"signature_delta","signature":"thinking-signature"}}"#,
            #"event: content_block_stop"#,
            #"data: {"type":"content_block_stop","index":0}"#,
            #"event: content_block_start"#,
            #"data: {"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"tool-1","name":"update_meal_log","input":{}}}"#,
            #"event: content_block_delta"#,
            #"data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\"description\":\"Chicken\",\"estimated_calories\":300,\"estimated_protein_grams\":50}"}}"#,
            #"event: content_block_stop"#,
            #"data: {"type":"content_block_stop","index":1}"#,
            #"event: message_delta"#,
            #"data: {"type":"message_delta","delta":{"stop_reason":"tool_use"}}"#
        ]

        for line in lines {
            emittedEvents.append(contentsOf: try processor.ingest(line: line))
        }

        let processedTurn = try processor.finish()
        emittedEvents.append(contentsOf: processedTurn.emittedEvents)

        XCTAssertEqual(emittedEvents, [
            .toolUseStart(id: "tool-1", name: "update_meal_log"),
            .toolUseDelta(
                id: "tool-1",
                partialJSON: #"{"description":"Chicken","estimated_calories":300,"estimated_protein_grams":50}"#
            ),
            .toolUseEnd(id: "tool-1")
        ])
        XCTAssertEqual(processedTurn.streamedTurn.stopReason, "tool_use")

        let contentBlocks = try encodedContentBlocks(from: processedTurn.streamedTurn.assistantBlocks)
        XCTAssertEqual(contentBlocks.map { $0["type"] as? String ?? "" }, ["thinking", "tool_use"])
        XCTAssertEqual(contentBlocks[0]["thinking"] as? String, "Need to log the meal before replying.")
        XCTAssertEqual(contentBlocks[0]["signature"] as? String, "thinking-signature")
    }

    func testPreservesOmittedThinkingSignatureWithoutVisibleDeltas() throws {
        var processor = ClaudeStreamProcessor()
        var emittedEvents: [StreamEvent] = []

        let lines = [
            #"event: content_block_start"#,
            #"data: {"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":""}}"#,
            #"event: content_block_delta"#,
            #"data: {"type":"content_block_delta","index":0,"delta":{"type":"signature_delta","signature":"omitted-signature"}}"#,
            #"event: content_block_stop"#,
            #"data: {"type":"content_block_stop","index":0}"#,
            #"event: message_delta"#,
            #"data: {"type":"message_delta","delta":{"stop_reason":"end_turn"}}"#
        ]

        for line in lines {
            emittedEvents.append(contentsOf: try processor.ingest(line: line))
        }

        let processedTurn = try processor.finish()
        emittedEvents.append(contentsOf: processedTurn.emittedEvents)

        XCTAssertEqual(emittedEvents, [])

        let contentBlocks = try encodedContentBlocks(from: processedTurn.streamedTurn.assistantBlocks)
        XCTAssertEqual(contentBlocks.count, 1)
        XCTAssertEqual(contentBlocks[0]["type"] as? String, "thinking")
        XCTAssertEqual(contentBlocks[0]["thinking"] as? String, "")
        XCTAssertEqual(contentBlocks[0]["signature"] as? String, "omitted-signature")
    }

    func testPreservesRedactedThinkingBlocks() throws {
        var processor = ClaudeStreamProcessor()

        _ = try processor.ingest(line: #"event: content_block_start"#)
        _ = try processor.ingest(
            line: #"data: {"type":"content_block_start","index":0,"content_block":{"type":"redacted_thinking","data":"encrypted-redacted-data"}}"#
        )
        _ = try processor.ingest(line: #"event: content_block_stop"#)
        _ = try processor.ingest(line: #"data: {"type":"content_block_stop","index":0}"#)

        let processedTurn = try processor.finish()
        let contentBlocks = try encodedContentBlocks(from: processedTurn.streamedTurn.assistantBlocks)

        XCTAssertEqual(contentBlocks.count, 1)
        XCTAssertEqual(contentBlocks[0]["type"] as? String, "redacted_thinking")
        XCTAssertEqual(contentBlocks[0]["data"] as? String, "encrypted-redacted-data")
    }

    func testThrowsOnStreamErrorEvent() {
        var processor = ClaudeStreamProcessor()

        XCTAssertThrowsError(
            try {
                _ = try processor.ingest(line: #"event: error"#)
                _ = try processor.ingest(line: #"data: {"type":"error","error":{"type":"invalid_request_error","message":"boom"}}"#)
                _ = try processor.finish()
            }()
        ) { error in
            XCTAssertEqual(error.localizedDescription, "boom")
        }
    }

    private func encodedContentBlocks(from blocks: [APIMessageContent]) throws -> [[String: Any]] {
        let data = try JSONEncoder().encode(APIMessage(role: "assistant", content: blocks))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try XCTUnwrap(json["content"] as? [[String: Any]])
    }
}

import Foundation
import XCTest
@testable import Ledger

final class LedgerLiveAPITests: XCTestCase {
    func testPlainGreetingRoundTrip() async throws {
        try requireLiveAPI()

        let client = ClaudeClient()
        let stream = await client.streamMessage(
            messages: [Message(role: .user, content: "Hi", timestamp: Date())],
            profile: "No saved profile yet.",
            todayLog: nil,
            tools: CoachTools.all
        )

        var collectedText = ""
        var sawMessageStop = false

        for try await event in stream {
            switch event {
            case .textDelta(let delta):
                collectedText += delta
            case .messageStop:
                sawMessageStop = true
            case .toolUseStart, .toolUseDelta, .toolUseEnd:
                break
            }
        }

        XCTAssertFalse(collectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertTrue(sawMessageStop)
    }

    func testMealMessageCompletesToolUseTurn() async throws {
        try requireLiveAPI()

        let client = ClaudeClient()
        let stream = await client.streamMessage(
            messages: [Message(role: .user, content: "had 2 factor meals and 200g of chicken", timestamp: Date())],
            profile: "No saved profile yet.",
            todayLog: nil,
            tools: CoachTools.all
        )

        var toolNames: [String] = []
        var toolJSONByID: [String: String] = [:]
        var didStop = false
        var collectedText = ""

        for try await event in stream {
            switch event {
            case .toolUseStart(let id, let name):
                toolNames.append(name)
                toolJSONByID[id] = ""
            case .toolUseDelta(let id, let partialJSON):
                toolJSONByID[id, default: ""] += partialJSON
            case .toolUseEnd(let id):
                let json = toolJSONByID[id] ?? ""
                XCTAssertFalse(json.isEmpty)
                await client.completeToolUse(id: id, content: "Meal logged.", isError: false)
            case .textDelta(let delta):
                collectedText += delta
            case .messageStop:
                didStop = true
            }
        }

        XCTAssertTrue(toolNames.contains("update_meal_log"))
        XCTAssertTrue(didStop)
        XCTAssertFalse(collectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private func requireLiveAPI() throws {
        guard ProcessInfo.processInfo.environment["LEDGER_RUN_LIVE_API_TESTS"] == "1" else {
            throw XCTSkip("Live API tests are opt-in. Set LEDGER_RUN_LIVE_API_TESTS=1.")
        }

        guard ClaudeClient().hasAPIKeyConfigured else {
            throw XCTSkip("No Anthropic API key configured.")
        }
    }
}

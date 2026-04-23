import Foundation
import XCTest
@testable import Ledger

final class LedgerLiveAPITests: XCTestCase {
    func testPlainGreetingRoundTrip() async throws {
        try requireLiveAPI()

        let client = ClaudeClient()
        let stream = await client.streamMessage(
            messages: [Message(role: .user, content: "Hi", timestamp: Date())],
            contextBlock: "## Who this person is\nNo saved profile yet.",
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
            contextBlock: "## Who this person is\nNo saved profile yet.",
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

    func testActiveStatePromptReturnsMarkdown() async throws {
        try requireLiveAPI()

        let client = ClaudeClient()
        let text = try await client.generateText(
            systemPrompt: MemoryMaintainer.activeStateSystemPrompt,
            userPrompt: """
            {
              "windowStart": "2026-04-15",
              "windowEnd": "2026-04-22",
              "todayMarkdown": "Meals total: 1200 cal, 110g protein",
              "dailyStats": [
                {"date":"2026-04-21","calories":2200,"protein":160,"trained":true,"hrv":"33","sleep":"7h 12m","loggedAnything":true}
              ],
              "latestMetrics": [
                {"type":"weight","value":"81.8kg","context":"morning","observedAt":"2026-04-22 08:00"}
              ],
              "trainingStreakDays": 1,
              "loggingStreakDays": 1,
              "workingWeights": [
                {"exercise":"Bench press","loadText":"100kg","observedAt":"2026-04-22 18:00","summary":"3x5 @ 100kg"}
              ]
            }
            """,
            maxTokens: 300
        )

        XCTAssertFalse(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertTrue(text.contains("100kg"))
    }

    func testDailySummaryPromptReturnsSingleParagraph() async throws {
        try requireLiveAPI()

        let client = ClaudeClient()
        let text = try await client.generateText(
            systemPrompt: MemoryMaintainer.dailySummarySystemPrompt,
            userPrompt: """
            {
              "date": "2026-04-22",
              "keyStats": {"calories": 1200, "protein": 110, "trained": true, "hrv": "33", "sleep": "7h 12m"},
              "todayMarkdown": "Meals total: 1200 cal, 110g protein\\n- 2 Factor meals + 200g chicken\\n\\nTraining\\n- Bench press — 3x5 @ 100kg",
              "messages": [
                {"role":"user","content":"had 2 factor meals and 200g of chicken"},
                {"role":"user","content":"bench 3x5 @ 100kg"}
              ]
            }
            """,
            maxTokens: 180
        )

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertFalse(trimmed.isEmpty)
        XCTAssertFalse(trimmed.contains("\n\n"))
    }

    func testPatternMaintenancePromptReturnsDecodableJSON() async throws {
        try requireLiveAPI()

        let client = ClaudeClient()
        let text = try await client.generateText(
            systemPrompt: MemoryMaintainer.patternsSystemPrompt,
            userPrompt: """
            {
              "summaries": [
                {"date":"2026-04-20","summaryText":"It was a social day and protein still ran light.","keyStats":{"calories":2200,"protein":105,"trained":false,"hrv":"28","sleep":"6h 10m"}},
                {"date":"2026-04-21","summaryText":"Another social day and protein lagged behind target.","keyStats":{"calories":2300,"protein":110,"trained":false,"hrv":"29","sleep":"6h 20m"}}
              ],
              "currentPatterns": []
            }
            """,
            maxTokens: 300
        )

        let data = try XCTUnwrap(text.data(using: .utf8))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(json["operations"] as? [Any])
    }

    func testIdentityUpdatePromptReturnsDecodableJSON() async throws {
        try requireLiveAPI()

        let client = ClaudeClient()
        let text = try await client.generateText(
            systemPrompt: MemoryMaintainer.identityUpdateSystemPrompt,
            userPrompt: """
            {
              "currentIdentityMarkdown": "## Goals\\n- goal_weight: 80kg",
              "summaries": [
                {"date":"2026-04-21","summaryText":"User explicitly said they want to cut to 78kg.","keyStats":{"calories":2200,"protein":160,"trained":true,"hrv":null,"sleep":null}}
              ],
              "currentPatterns": []
            }
            """,
            maxTokens: 250
        )

        let data = try XCTUnwrap(text.data(using: .utf8))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(json["proposals"] as? [Any])
    }

    func testHistoricalQuestionCanCompleteArchiveSearchTurn() async throws {
        try requireLiveAPI()

        let client = ClaudeClient()
        let stream = await client.streamMessage(
            messages: [Message(role: .user, content: "How was travel last month?", timestamp: Date())],
            contextBlock: """
            ## Who this person is
            - goal_weight: 78kg

            ## Patterns observed
            - None yet.

            ## Where they are right now
            No active state snapshot yet.

            ## Recent days
            No daily summaries yet.

            ## Today so far
            Nothing logged yet today.
            """,
            tools: CoachTools.all
        )

        var sawArchiveTool = false
        var sawMessageStop = false

        for try await event in stream {
            switch event {
            case .toolUseStart(let id, let name):
                if name == "search_archive" {
                    sawArchiveTool = true
                }
                await client.completeToolUse(
                    id: id,
                    content: "- month 2026-03-01 → 2026-03-31: Travel pulled structure apart and sleep ran short.",
                    isError: false
                )
            case .messageStop:
                sawMessageStop = true
            case .textDelta, .toolUseDelta, .toolUseEnd:
                break
            }
        }

        XCTAssertTrue(sawArchiveTool)
        XCTAssertTrue(sawMessageStop)
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

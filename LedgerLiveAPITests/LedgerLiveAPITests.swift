import Foundation
import SwiftData
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

    func testSummarizationRunAgainstSeedData() async throws {
        try requireLiveAPI()
        guard ProcessInfo.processInfo.environment["LEDGER_RUN_SEED_SUMMARIZATION"] == "1" else {
            throw XCTSkip("Seed-data summarization run is opt-in. Set LEDGER_RUN_SEED_SUMMARIZATION=1.")
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt

        let baseDate = calendar.date(
            from: DateComponents(
                timeZone: calendar.timeZone,
                year: 2026, month: 4, day: 23, hour: 0, minute: 0
            )
        )!
        let rollupNow = calendar.date(
            from: DateComponents(
                timeZone: calendar.timeZone,
                year: 2026, month: 6, day: 1, hour: 0, minute: 0
            )
        )!

        let clock = LedgerTestClock(initialDate: baseDate, calendar: calendar)

        let container = try LedgerPersistentModels.makeContainer(inMemory: true)
        let didSeed = try HistoryPreviewSeeder.seedIfNeeded(
            in: container,
            calendar: calendar,
            now: clock.now()
        )
        XCTAssertTrue(didSeed, "Seeder should have inserted rows into the empty container.")

        let client = ClaudeClient()
        let loggingClient = LoggingTextGenerator(underlying: client)
        let maintainer = MemoryMaintainer(
            modelContainer: container,
            textGenerator: loggingClient,
            calendar: calendar,
            now: { clock.now() }
        )

        let dayFormatter = DateFormatter()
        dayFormatter.calendar = calendar
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.timeZone = calendar.timeZone
        dayFormatter.dateFormat = "yyyy-MM-dd"

        print("\n\n########## SEED INPUT INVENTORY ##########\n")
        let inventoryContext = ModelContext(container)
        let allMeals = try inventoryContext.fetch(
            FetchDescriptor<StoredMeal>(sortBy: [SortDescriptor(\.date)])
        )
        let allWorkouts = try inventoryContext.fetch(
            FetchDescriptor<StoredWorkoutSet>(sortBy: [SortDescriptor(\.date)])
        )
        let allMetrics = try inventoryContext.fetch(
            FetchDescriptor<StoredMetric>(sortBy: [SortDescriptor(\.date)])
        )
        let allMessages = try inventoryContext.fetch(
            FetchDescriptor<StoredMessage>(sortBy: [SortDescriptor(\.timestamp)])
        )
        print("baseDate (now for phases 1-4): \(dayFormatter.string(from: baseDate))")
        print("rollupNow (now for phases 5-6): \(dayFormatter.string(from: rollupNow))")
        print("StoredMeal rows: \(allMeals.count)")
        print("StoredWorkoutSet rows: \(allWorkouts.count)")
        print("StoredMetric rows: \(allMetrics.count)")
        print("StoredMessage rows: \(allMessages.count)")
        if let first = allMeals.first, let last = allMeals.last {
            print("Meal date range: \(dayFormatter.string(from: first.date)) .. \(dayFormatter.string(from: last.date))")
        }

        print("\n\n########## PHASE 1: summarizeToday (12 calls) ##########\n")
        let seedOffsets = [14, 12, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1]
        for offset in seedOffsets {
            guard
                let dayStart = calendar.date(byAdding: .day, value: -offset, to: baseDate),
                let dayNoon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: dayStart)
            else {
                continue
            }
            clock.set(dayNoon)
            print("\n--- summarizeToday for \(dayFormatter.string(from: dayStart)) ---")
            try await maintainer.summarizeToday()
        }
        clock.set(baseDate)

        print("\n\n########## PHASE 2: updateActiveState ##########\n")
        try await maintainer.updateActiveState()

        print("\n\n########## PHASE 3: updatePatterns ##########\n")
        try await maintainer.updatePatterns()

        print("\n\n########## PHASE 4: proposeIdentityUpdates ##########\n")
        do {
            try await maintainer.proposeIdentityUpdates()
            print("[phase 4] completed without error")
        } catch {
            print("[phase 4] maintainer threw after LLM call: \(error). See logged response above for the raw text that failed to decode.")
        }

        print("\n\n########## PHASE 5: rollupWeek (now advanced to \(dayFormatter.string(from: rollupNow))) ##########\n")
        clock.set(rollupNow)
        try await maintainer.rollupWeek()

        print("\n\n########## PHASE 6: rollupMonth ##########\n")
        try await maintainer.rollupMonth()

        print("\n\n########## FINAL STATE ##########\n")
        let finalContext = ModelContext(container)
        let finalDailies = try finalContext.fetch(
            FetchDescriptor<DailySummary>(sortBy: [SortDescriptor(\.date)])
        )
        let finalWeeklies = try finalContext.fetch(
            FetchDescriptor<WeeklySummary>(sortBy: [SortDescriptor(\.startDate)])
        )
        let finalMonthlies = try finalContext.fetch(
            FetchDescriptor<MonthlySummary>(sortBy: [SortDescriptor(\.startDate)])
        )
        let finalPatterns = try finalContext.fetch(
            FetchDescriptor<Pattern>(sortBy: [SortDescriptor(\.key)])
        )
        let finalIdentity = try finalContext.fetch(FetchDescriptor<IdentityProfile>()).first
        let finalActiveState = try finalContext.fetch(FetchDescriptor<ActiveStateSnapshot>()).first

        print("DailySummary rows: \(finalDailies.count)")
        print("WeeklySummary rows: \(finalWeeklies.count)")
        print("MonthlySummary rows: \(finalMonthlies.count)")
        print("Pattern rows: \(finalPatterns.count)")
        print("IdentityProfile present: \(finalIdentity != nil) (content chars: \(finalIdentity?.markdownContent.count ?? 0))")
        print("ActiveStateSnapshot present: \(finalActiveState != nil) (content chars: \(finalActiveState?.markdownContent.count ?? 0))")
        print("")

        if let snapshot = finalActiveState {
            print("--- ActiveStateSnapshot ---")
            print(snapshot.markdownContent)
            print("")
        }
        for pattern in finalPatterns {
            print("--- Pattern \(pattern.key) [\(pattern.confidence.rawValue)] ---")
            print(pattern.descriptionText)
            print("evidence: \(pattern.evidenceNote)")
            print("first=\(dayFormatter.string(from: pattern.firstObserved)) last=\(dayFormatter.string(from: pattern.lastReinforced))")
            print("")
        }
        if let identity = finalIdentity {
            print("--- IdentityProfile ---")
            print(identity.markdownContent)
            print("")
        }
        for daily in finalDailies {
            print("--- DailySummary \(dayFormatter.string(from: daily.date)) (not yet archived) ---")
            print(daily.summaryText)
            print("stats: \(daily.keyStats)")
            print("")
        }
        for weekly in finalWeeklies {
            print("--- WeeklySummary \(dayFormatter.string(from: weekly.startDate)) → \(dayFormatter.string(from: weekly.endDate)) ---")
            print(weekly.summaryText)
            print("stats: \(weekly.keyStats)")
            print("")
        }
        for monthly in finalMonthlies {
            print("--- MonthlySummary \(dayFormatter.string(from: monthly.startDate)) → \(dayFormatter.string(from: monthly.endDate)) ---")
            print(monthly.summaryText)
            print("stats: \(monthly.keyStats)")
            print("")
        }

        print("########## END ##########\n")
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

actor LoggingTextGenerator: MemoryTextGeneratingClient {
    nonisolated let hasAPIKeyConfigured: Bool
    private let underlying: any MemoryTextGeneratingClient
    private var callIndex = 0
    private var seenSystemPromptKeys = Set<String>()

    init(underlying: any MemoryTextGeneratingClient) {
        self.underlying = underlying
        self.hasAPIKeyConfigured = underlying.hasAPIKeyConfigured
    }

    func generateText(
        systemPrompt: String,
        userPrompt: String,
        maxTokens: Int
    ) async throws -> String {
        callIndex += 1
        let idx = callIndex
        let systemKey = String(systemPrompt.prefix(80))
        let alreadySeen = seenSystemPromptKeys.contains(systemKey)
        seenSystemPromptKeys.insert(systemKey)

        print(">>> LLM CALL #\(idx)  maxTokens=\(maxTokens)")
        if alreadySeen {
            print("--- systemPrompt: (same as an earlier call; elided) ---")
        } else {
            print("--- systemPrompt ---")
            print(systemPrompt)
        }
        print("--- userPrompt ---")
        print(userPrompt)
        do {
            let response = try await underlying.generateText(
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                maxTokens: maxTokens
            )
            print("--- response ---")
            print(response)
            print("<<< LLM CALL #\(idx) complete\n")
            return response
        } catch {
            print("--- error from underlying client ---")
            print("\(error)")
            print("<<< LLM CALL #\(idx) failed\n")
            throw error
        }
    }
}

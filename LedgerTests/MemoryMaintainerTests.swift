import Foundation
import SwiftData
import XCTest
@testable import Ledger

final class MemoryMaintainerTests: XCTestCase {
    func testUpdateActiveStateUpsertsSnapshotAndIncludesParsedWorkingWeights() async throws {
        let container = try TestHelpers.makeInMemoryContainer()
        let context = ModelContext(container)
        let now = Date(timeIntervalSince1970: 1_777_777_200)
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: now)

        context.insert(
            StoredWorkoutSet(
                date: calendar.date(byAdding: .hour, value: 18, to: today) ?? today,
                exercise: "Bench press",
                summary: "3x5 @ 100kg",
                notes: nil
            )
        )
        context.insert(
            StoredMetric(
                date: calendar.date(byAdding: .hour, value: 7, to: today) ?? today,
                type: "weight",
                value: "81.8kg",
                context: nil
            )
        )
        context.insert(
            StoredMeal(
                date: calendar.date(byAdding: .hour, value: 12, to: today) ?? today,
                descriptionText: "Chicken rice box",
                calories: 760,
                protein: 57
            )
        )
        try context.save()

        let generator = StubMemoryTextGenerator(
            responses: [
                "### Snapshot\n- Weight: 81.8kg\n- Bench: 100kg",
                "### Snapshot\n- Weight: 81.7kg\n- Bench: 100kg"
            ]
        )
        let maintainer = MemoryMaintainer(
            modelContainer: container,
            textGenerator: generator,
            calendar: calendar,
            now: { now }
        )

        try await maintainer.updateActiveState()
        try await maintainer.updateActiveState()

        let snapshots = try context.fetch(FetchDescriptor<ActiveStateSnapshot>())
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertTrue(snapshots.first?.markdownContent.contains("81.7kg") == true)

        let prompts = await generator.promptsSnapshot()
        XCTAssertEqual(prompts.count, 2)
        XCTAssertTrue(prompts[0].userPrompt.contains("100kg"))
        XCTAssertTrue(prompts[0].userPrompt.contains("\"trainingStreakDays\""))
    }

    func testSummarizeTodayUpsertsSingleDailySummary() async throws {
        let container = try TestHelpers.makeInMemoryContainer()
        let context = ModelContext(container)
        let now = Date(timeIntervalSince1970: 1_777_777_200)
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: now)

        context.insert(
            StoredMessage(
                role: "user",
                content: "Had 2 factor meals and trained bench.",
                timestamp: calendar.date(byAdding: .hour, value: 20, to: today) ?? today
            )
        )
        context.insert(
            StoredMeal(
                date: calendar.date(byAdding: .hour, value: 13, to: today) ?? today,
                descriptionText: "2 Factor meals",
                calories: 1040,
                protein: 78
            )
        )
        try context.save()

        let generator = StubMemoryTextGenerator(
            responses: [
                "Productive day with solid intake and a clean training report.",
                "Rewritten daily summary after rerun."
            ]
        )
        let maintainer = MemoryMaintainer(
            modelContainer: container,
            textGenerator: generator,
            calendar: calendar,
            now: { now }
        )

        try await maintainer.summarizeToday()
        try await maintainer.summarizeToday()

        let summaries = try context.fetch(FetchDescriptor<DailySummary>())
        XCTAssertEqual(summaries.count, 1)
        XCTAssertEqual(summaries.first?.summaryText, "Rewritten daily summary after rerun.")
    }

    func testUpdatePatternsAppliesAddAndRemoveOperations() async throws {
        let container = try TestHelpers.makeInMemoryContainer()
        let context = ModelContext(container)
        let now = Date(timeIntervalSince1970: 1_777_777_200)
        let calendar = Calendar(identifier: .gregorian)

        context.insert(
            DailySummary(
                date: calendar.startOfDay(for: now.addingTimeInterval(-2 * 86_400)),
                summaryText: "Protein was low again after a social dinner.",
                keyStats: .init(calories: 2200, protein: 105, trained: false, hrv: "28", sleep: "6h 10m")
            )
        )
        context.insert(
            DailySummary(
                date: calendar.startOfDay(for: now.addingTimeInterval(-1 * 86_400)),
                summaryText: "Another social day and protein lagged behind target.",
                keyStats: .init(calories: 2300, protein: 110, trained: false, hrv: "29", sleep: "6h 30m")
            )
        )
        context.insert(
            Pattern(
                key: "remove_me",
                descriptionText: "Obsolete pattern",
                evidenceNote: "Old evidence",
                confidence: .low,
                firstObserved: now.addingTimeInterval(-40 * 86_400),
                lastReinforced: now.addingTimeInterval(-35 * 86_400)
            )
        )
        try context.save()

        let generator = StubMemoryTextGenerator(
            responses: [
                """
                {
                  "operations": [
                    {
                      "action": "remove",
                      "key": "remove_me",
                      "evidenceNote": "No support in the recent window."
                    },
                    {
                      "action": "add",
                      "key": "protein_social_days",
                      "description": "Protein tends to lag on social days.",
                      "evidenceNote": "Seen on multiple recent social days.",
                      "confidence": "low",
                      "firstObserved": "2026-04-20",
                      "lastReinforced": "2026-04-21"
                    }
                  ]
                }
                """
            ]
        )
        let maintainer = MemoryMaintainer(
            modelContainer: container,
            textGenerator: generator,
            calendar: calendar,
            now: { now }
        )

        try await maintainer.updatePatterns()

        let patterns = try context.fetch(FetchDescriptor<Pattern>())
        XCTAssertEqual(patterns.count, 1)
        XCTAssertEqual(patterns.first?.key, "protein_social_days")
    }

    func testProposeIdentityUpdatesAppliesOnlyHighConfidenceFactualChanges() async throws {
        let container = try TestHelpers.makeInMemoryContainer()
        let context = ModelContext(container)
        let now = Date(timeIntervalSince1970: 1_777_777_200)
        let calendar = Calendar(identifier: .gregorian)

        context.insert(
            DailySummary(
                date: calendar.startOfDay(for: now.addingTimeInterval(-1 * 86_400)),
                summaryText: "User explicitly said they want to cut to 78kg.",
                keyStats: .init(calories: 2200, protein: 160, trained: true, hrv: nil, sleep: nil)
            )
        )
        try context.save()

        let generator = StubMemoryTextGenerator(
            responses: [
                """
                {
                  "proposals": [
                    {
                      "kind": "factual",
                      "confidence": "high",
                      "key": "goal_weight",
                      "value": "78kg",
                      "rationale": "The user stated this directly."
                    },
                    {
                      "kind": "interpretive",
                      "confidence": "medium",
                      "key": "mindset",
                      "value": "responds well to pressure",
                      "rationale": "This is interpretive and should not auto-apply."
                    }
                  ]
                }
                """
            ]
        )
        let maintainer = MemoryMaintainer(
            modelContainer: container,
            textGenerator: generator,
            calendar: calendar,
            now: { now }
        )

        try await maintainer.proposeIdentityUpdates()

        let profiles = try context.fetch(FetchDescriptor<IdentityProfile>())
        XCTAssertEqual(profiles.count, 1)
        XCTAssertTrue(profiles.first?.markdownContent.contains("- goal_weight: 78kg") == true)
        XCTAssertFalse(profiles.first?.markdownContent.contains("mindset") == true)
    }

    func testRollupsCompressOldDailyAndWeeklySummaries() async throws {
        let container = try TestHelpers.makeInMemoryContainer()
        let context = ModelContext(container)
        let now = Date(timeIntervalSince1970: 1_777_777_200)
        let calendar = Calendar(identifier: .gregorian)
        let base = calendar.startOfDay(for: now.addingTimeInterval(-90 * 86_400))

        for offset in 0 ..< 3 {
            let date = calendar.date(byAdding: .day, value: offset, to: base) ?? base
            context.insert(
                DailySummary(
                    date: date,
                    summaryText: "Old training week entry \(offset).",
                    keyStats: .init(calories: 2200 + offset, protein: 150, trained: true, hrv: "32", sleep: "7h 00m")
                )
            )
        }
        try context.save()

        let generator = StubMemoryTextGenerator(
            responses: [
                "Archived week summary.",
                "Archived month summary."
            ]
        )
        let maintainer = MemoryMaintainer(
            modelContainer: container,
            textGenerator: generator,
            calendar: calendar,
            now: { now }
        )

        try await maintainer.rollupWeek()
        XCTAssertEqual(try context.fetch(FetchDescriptor<DailySummary>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WeeklySummary>()).count, 1)

        try await maintainer.rollupMonth()
        XCTAssertEqual(try context.fetch(FetchDescriptor<WeeklySummary>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<MonthlySummary>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<MonthlySummary>()).first?.summaryText, "Archived month summary.")
    }
}

private actor StubMemoryTextGenerator: MemoryTextGeneratingClient {
    nonisolated let hasAPIKeyConfigured = true

    private var responses: [String]
    private var prompts: [Prompt] = []

    init(responses: [String]) {
        self.responses = responses
    }

    func generateText(
        systemPrompt: String,
        userPrompt: String,
        maxTokens: Int
    ) async throws -> String {
        prompts.append(
            Prompt(
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                maxTokens: maxTokens
            )
        )

        guard !responses.isEmpty else {
            throw TestError()
        }

        return responses.removeFirst()
    }

    func promptsSnapshot() -> [Prompt] {
        prompts
    }

    struct Prompt: Equatable {
        let systemPrompt: String
        let userPrompt: String
        let maxTokens: Int
    }
}

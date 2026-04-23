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

    func testUpdatePatternsUpdatesExistingPatternAndPromotesConfidence() async throws {
        let container = try TestHelpers.makeInMemoryContainer()
        let context = ModelContext(container)
        let calendar = TestHelpers.makeUTCCalendar()
        let now = TestHelpers.makeDate(year: 2026, month: 4, day: 22, calendar: calendar)

        context.insert(
            DailySummary(
                date: TestHelpers.makeDate(year: 2026, month: 4, day: 19, calendar: calendar),
                summaryText: "It was a social day and protein still ran light.",
                keyStats: .init(calories: 2200, protein: 105, trained: false, hrv: "28", sleep: "6h 10m")
            )
        )
        context.insert(
            DailySummary(
                date: TestHelpers.makeDate(year: 2026, month: 4, day: 20, calendar: calendar),
                summaryText: "It was a social day and protein still ran light.",
                keyStats: .init(calories: 2300, protein: 110, trained: false, hrv: "29", sleep: "6h 20m")
            )
        )
        context.insert(
            DailySummary(
                date: TestHelpers.makeDate(year: 2026, month: 4, day: 21, calendar: calendar),
                summaryText: "It was a social day and protein still ran light.",
                keyStats: .init(calories: 2250, protein: 115, trained: false, hrv: "30", sleep: "6h 30m")
            )
        )
        context.insert(
            Pattern(
                key: "protein_social_days",
                descriptionText: "Protein drifts on social days.",
                evidenceNote: "Old evidence",
                confidence: .low,
                firstObserved: TestHelpers.makeDate(year: 2026, month: 3, day: 20, calendar: calendar),
                lastReinforced: TestHelpers.makeDate(year: 2026, month: 4, day: 1, calendar: calendar)
            )
        )
        try context.save()

        let generator = StubMemoryTextGenerator(
            responses: [
                """
                {
                  "operations": [
                    {
                      "action": "update",
                      "key": "protein_social_days",
                      "description": "Protein tends to lag on social days.",
                      "evidenceNote": "Repeated across recent social days with protein under 130g.",
                      "confidence": "medium",
                      "firstObserved": "2026-04-19",
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

        let pattern = try XCTUnwrap(
            context.fetch(
                FetchDescriptor<Pattern>(
                    predicate: #Predicate { $0.key == "protein_social_days" }
                )
            ).first
        )
        XCTAssertEqual(pattern.descriptionText, "Protein tends to lag on social days.")
        XCTAssertEqual(pattern.confidence, .medium)
        XCTAssertEqual(pattern.evidenceNote, "Repeated across recent social days with protein under 130g.")
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

    func testProposeIdentityUpdatesIgnoresLowerConfidenceChangesAndPreservesExistingProfile() async throws {
        let container = try TestHelpers.makeInMemoryContainer()
        let context = ModelContext(container)
        let calendar = TestHelpers.makeUTCCalendar()
        let now = TestHelpers.makeDate(year: 2026, month: 4, day: 22, calendar: calendar)

        context.insert(
            IdentityProfile(
                scope: IdentityProfile.defaultScope,
                markdownContent: """
                ## Goals
                - goal_weight: 80kg
                """,
                lastUpdated: now.addingTimeInterval(-86_400)
            )
        )
        context.insert(
            DailySummary(
                date: TestHelpers.makeDate(year: 2026, month: 4, day: 21, calendar: calendar),
                summaryText: "They seem more motivated lately.",
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
                      "confidence": "medium",
                      "key": "goal_weight",
                      "value": "78kg",
                      "rationale": "Not stated directly."
                    },
                    {
                      "kind": "interpretive",
                      "confidence": "high",
                      "key": "mindset",
                      "value": "more motivated",
                      "rationale": "Interpretive only."
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

        let profile = try XCTUnwrap(context.fetch(FetchDescriptor<IdentityProfile>()).first)
        XCTAssertTrue(profile.markdownContent.contains("- goal_weight: 80kg"))
        XCTAssertFalse(profile.markdownContent.contains("mindset"))
    }

    func testUpdatePatternsThrowsOnMalformedJSONAndLeavesExistingPatternsUntouched() async throws {
        let container = try TestHelpers.makeInMemoryContainer()
        let context = ModelContext(container)
        let calendar = TestHelpers.makeUTCCalendar()
        let now = TestHelpers.makeDate(year: 2026, month: 4, day: 22, calendar: calendar)

        context.insert(
            DailySummary(
                date: TestHelpers.makeDate(year: 2026, month: 4, day: 21, calendar: calendar),
                summaryText: "It was a social day and protein still ran light.",
                keyStats: .init(calories: 2200, protein: 105, trained: false, hrv: nil, sleep: nil)
            )
        )
        context.insert(
            Pattern(
                key: "protein_social_days",
                descriptionText: "Protein tends to lag on social days.",
                evidenceNote: "Existing evidence",
                confidence: .low,
                firstObserved: TestHelpers.makeDate(year: 2026, month: 4, day: 20, calendar: calendar),
                lastReinforced: TestHelpers.makeDate(year: 2026, month: 4, day: 21, calendar: calendar)
            )
        )
        try context.save()

        let generator = StubMemoryTextGenerator(responses: ["not json"])
        let maintainer = MemoryMaintainer(
            modelContainer: container,
            textGenerator: generator,
            calendar: calendar,
            now: { now }
        )

        do {
            try await maintainer.updatePatterns()
            XCTFail("Expected malformed JSON to throw.")
        } catch {}

        let patterns = try context.fetch(FetchDescriptor<Pattern>())
        XCTAssertEqual(patterns.count, 1)
        XCTAssertEqual(patterns.first?.evidenceNote, "Existing evidence")
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

    func testRollupWeekUpdatesExistingSummaryAndLeavesCurrentWeekUntouched() async throws {
        let container = try TestHelpers.makeInMemoryContainer()
        let context = ModelContext(container)
        let calendar = TestHelpers.makeUTCCalendar()
        let now = TestHelpers.makeDate(year: 2026, month: 4, day: 22, hour: 12, calendar: calendar)
        let oldEntryDate = TestHelpers.makeDate(year: 2026, month: 3, day: 16, calendar: calendar)
        let oldWeekInterval = try XCTUnwrap(calendar.dateInterval(of: .weekOfYear, for: oldEntryDate))
        let oldWeekStart = oldWeekInterval.start
        let oldWeekEnd = calendar.date(byAdding: .day, value: -1, to: oldWeekInterval.end) ?? oldWeekStart

        context.insert(
            DailySummary(
                date: oldWeekStart,
                summaryText: "Old week entry 1.",
                keyStats: .init(calories: 2000, protein: 140, trained: false, hrv: "30", sleep: "7h 00m")
            )
        )
        context.insert(
            DailySummary(
                date: calendar.date(byAdding: .day, value: 1, to: oldWeekStart) ?? oldWeekStart,
                summaryText: "Old week entry 2.",
                keyStats: .init(calories: 2200, protein: 160, trained: true, hrv: "32", sleep: "7h 20m")
            )
        )
        context.insert(
            DailySummary(
                date: calendar.startOfDay(for: now),
                summaryText: "Current week entry.",
                keyStats: .init(calories: 2400, protein: 180, trained: true, hrv: "34", sleep: "7h 30m")
            )
        )
        context.insert(
            WeeklySummary(
                startDate: oldWeekStart,
                endDate: oldWeekEnd,
                summaryText: "Existing weekly summary.",
                keyStats: .init(calories: 1000, protein: 100, trained: false, hrv: "25", sleep: "6h 00m")
            )
        )
        try context.save()

        let generator = StubMemoryTextGenerator(
            responses: [
                "Archived old week summary."
            ]
        )
        let maintainer = MemoryMaintainer(
            modelContainer: container,
            textGenerator: generator,
            calendar: calendar,
            now: { now }
        )

        try await maintainer.rollupWeek()

        let weekly = try context.fetch(
            FetchDescriptor<WeeklySummary>(
                sortBy: [SortDescriptor(\.startDate, order: .forward)]
            )
        )
        let remainingDaily = try context.fetch(
            FetchDescriptor<DailySummary>(
                sortBy: [SortDescriptor(\.date, order: .forward)]
            )
        )

        XCTAssertEqual(weekly.count, 1)
        XCTAssertEqual(weekly.first?.summaryText, "Archived old week summary.")
        XCTAssertEqual(weekly.first?.keyStats.calories, 2100)
        XCTAssertEqual(weekly.first?.keyStats.protein, 150)
        XCTAssertEqual(remainingDaily.count, 1)
        XCTAssertEqual(remainingDaily.first?.summaryText, "Current week entry.")
    }

    func testRollupMonthAggregatesStatsAndDoesNotTouchCurrentMonth() async throws {
        let container = try TestHelpers.makeInMemoryContainer()
        let context = ModelContext(container)
        let calendar = TestHelpers.makeUTCCalendar()
        let now = TestHelpers.makeDate(year: 2026, month: 4, day: 22, hour: 12, calendar: calendar)

        context.insert(
            WeeklySummary(
                startDate: TestHelpers.makeDate(year: 2026, month: 3, day: 2, calendar: calendar),
                endDate: TestHelpers.makeDate(year: 2026, month: 3, day: 8, calendar: calendar),
                summaryText: "March week 1",
                keyStats: .init(calories: 2100, protein: 145, trained: true, hrv: "31", sleep: "7h 00m")
            )
        )
        context.insert(
            WeeklySummary(
                startDate: TestHelpers.makeDate(year: 2026, month: 3, day: 9, calendar: calendar),
                endDate: TestHelpers.makeDate(year: 2026, month: 3, day: 15, calendar: calendar),
                summaryText: "March week 2",
                keyStats: .init(calories: 2300, protein: 155, trained: false, hrv: "33", sleep: "7h 20m")
            )
        )
        context.insert(
            WeeklySummary(
                startDate: TestHelpers.makeDate(year: 2026, month: 4, day: 13, calendar: calendar),
                endDate: TestHelpers.makeDate(year: 2026, month: 4, day: 19, calendar: calendar),
                summaryText: "Current month week",
                keyStats: .init(calories: 2400, protein: 180, trained: true, hrv: "34", sleep: "7h 40m")
            )
        )
        context.insert(
            MonthlySummary(
                startDate: TestHelpers.makeDate(year: 2026, month: 3, day: 1, calendar: calendar),
                endDate: TestHelpers.makeDate(year: 2026, month: 3, day: 31, calendar: calendar),
                summaryText: "Existing March summary.",
                keyStats: .init(calories: 1000, protein: 100, trained: false, hrv: "20", sleep: "5h 00m")
            )
        )
        try context.save()

        let generator = StubMemoryTextGenerator(responses: ["Archived March summary."])
        let maintainer = MemoryMaintainer(
            modelContainer: container,
            textGenerator: generator,
            calendar: calendar,
            now: { now }
        )

        try await maintainer.rollupMonth()

        let monthly = try context.fetch(FetchDescriptor<MonthlySummary>())
        let remainingWeekly = try context.fetch(
            FetchDescriptor<WeeklySummary>(
                sortBy: [SortDescriptor(\.startDate, order: .forward)]
            )
        )

        XCTAssertEqual(monthly.count, 1)
        XCTAssertEqual(monthly.first?.summaryText, "Archived March summary.")
        XCTAssertEqual(monthly.first?.keyStats.calories, 2200)
        XCTAssertEqual(monthly.first?.keyStats.protein, 150)
        XCTAssertEqual(remainingWeekly.count, 1)
        XCTAssertEqual(remainingWeekly.first?.summaryText, "Current month week")
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

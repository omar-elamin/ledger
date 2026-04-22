import Foundation
import SwiftData
import XCTest
@testable import Ledger

final class ContextBuilderTests: XCTestCase {
    func testBuildChatContextUsesExpectedSectionOrderAndFormatting() throws {
        let container = try TestHelpers.makeInMemoryContainer()
        let context = ModelContext(container)
        let now = Date(timeIntervalSince1970: 1_777_777_200)
        let calendar = Calendar(identifier: .gregorian)

        try seedSampleContext(in: context, now: now, calendar: calendar)

        let builder = ContextBuilder(
            modelContext: context,
            calendar: calendar,
            now: { now }
        )

        let contextBlock = builder.buildChatContext()

        XCTAssertTrue(contextBlock.hasPrefix("## Who this person is"))
        XCTAssertTrue(contextBlock.contains("## Patterns observed"))
        XCTAssertTrue(contextBlock.contains("## Where they are right now"))
        XCTAssertTrue(contextBlock.contains("## Recent days"))
        XCTAssertTrue(contextBlock.contains("## Today so far"))
        XCTAssertTrue(contextBlock.contains("- [medium] Protein tends to lag on social days."))
        XCTAssertFalse(contextBlock.contains("low_confidence_pattern"))
        XCTAssertTrue(contextBlock.contains("Meals total:"))
        XCTAssertTrue(contextBlock.contains("Body / recovery"))
    }

    func testArchiveSearchReturnsNewestMatchesFirst() throws {
        let container = try TestHelpers.makeInMemoryContainer()
        let context = ModelContext(container)
        let now = Date(timeIntervalSince1970: 1_777_777_200)

        context.insert(
            WeeklySummary(
                startDate: now.addingTimeInterval(-21 * 86_400),
                endDate: now.addingTimeInterval(-15 * 86_400),
                summaryText: "Travel week with poor sleep.",
                keyStats: .empty
            )
        )
        context.insert(
            WeeklySummary(
                startDate: now.addingTimeInterval(-14 * 86_400),
                endDate: now.addingTimeInterval(-8 * 86_400),
                summaryText: "Travel again, better protein floor.",
                keyStats: .empty
            )
        )
        context.insert(
            MonthlySummary(
                startDate: now.addingTimeInterval(-60 * 86_400),
                endDate: now.addingTimeInterval(-31 * 86_400),
                summaryText: "A month with travel every week.",
                keyStats: .empty
            )
        )
        try context.save()

        let builder = ContextBuilder(modelContext: context, now: { now })
        let matches = try builder.archiveMatches(query: "travel")

        XCTAssertEqual(matches.count, 3)
        XCTAssertTrue(matches[0].summaryText.contains("Travel again"))
        XCTAssertTrue(matches[1].summaryText.contains("Travel week"))
        XCTAssertTrue(matches[2].summaryText.contains("travel every week"))
    }

    func testContextStaysWithinRoughTokenBudget() throws {
        let container = try TestHelpers.makeInMemoryContainer()
        let context = ModelContext(container)
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_777_777_200)

        context.insert(
            IdentityProfile(
                scope: IdentityProfile.defaultScope,
                markdownContent: """
                ## Goals
                - goal: cut to 78kg

                ## Preferences
                - training_time: evenings
                """,
                lastUpdated: now
            )
        )
        context.insert(
            ActiveStateSnapshot(
                scope: ActiveStateSnapshot.defaultScope,
                markdownContent: "Current averages are stable and training volume is intact.",
                generatedAt: now
            )
        )

        for index in 0 ..< 28 {
            let day = calendar.date(byAdding: .day, value: -index - 1, to: now) ?? now
            context.insert(
                DailySummary(
                    date: calendar.startOfDay(for: day),
                    summaryText: Array(repeating: "Protein stayed high and training remained consistent.", count: 4).joined(separator: " "),
                    keyStats: .init(calories: 2300, protein: 165, trained: index % 2 == 0, hrv: "33", sleep: "7h 12m")
                )
            )
        }
        try context.save()

        let builder = ContextBuilder(
            modelContext: context,
            calendar: calendar,
            now: { now }
        )
        let contextBlock = builder.buildChatContext()
        let approximateTokenCount = contextBlock.split(whereSeparator: \.isWhitespace).count

        XCTAssertLessThan(approximateTokenCount, 6_000)
    }

    func testSampleContextFixtureForManualInspection() throws {
        let container = try TestHelpers.makeInMemoryContainer()
        let context = ModelContext(container)
        let now = Date(timeIntervalSince1970: 1_777_777_200)
        let calendar = Calendar(identifier: .gregorian)

        try seedSampleContext(in: context, now: now, calendar: calendar)

        let contextBlock = ContextBuilder(
            modelContext: context,
            calendar: calendar,
            now: { now }
        )
        .buildChatContext()

        print("\nSAMPLE_CONTEXT_START\n\(contextBlock)\nSAMPLE_CONTEXT_END\n")

        XCTAssertTrue(contextBlock.contains("## Who this person is"))
    }

    private func seedSampleContext(
        in context: ModelContext,
        now: Date,
        calendar: Calendar
    ) throws {
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: today) ?? today

        context.insert(
            IdentityProfile(
                scope: IdentityProfile.defaultScope,
                markdownContent: """
                ## Goals
                - goal: cut to 78kg

                ## Preferences
                - training_time: evenings
                """,
                lastUpdated: now
            )
        )
        context.insert(
            Pattern(
                key: "protein_social_days",
                descriptionText: "Protein tends to lag on social days.",
                evidenceNote: "Seen across several recent social meals.",
                confidence: .medium,
                firstObserved: twoDaysAgo,
                lastReinforced: yesterday
            )
        )
        context.insert(
            Pattern(
                key: "low_confidence_pattern",
                descriptionText: "This should not show up.",
                evidenceNote: "Single weak observation.",
                confidence: .low,
                firstObserved: yesterday,
                lastReinforced: yesterday
            )
        )
        context.insert(
            ActiveStateSnapshot(
                scope: ActiveStateSnapshot.defaultScope,
                markdownContent: """
                ### Snapshot
                - Weight: 81.8kg
                - Bench working weight: 100kg
                """,
                generatedAt: now
            )
        )
        context.insert(
            DailySummary(
                date: twoDaysAgo,
                summaryText: "Drank the night before, HRV stayed suppressed, and training was skipped.",
                keyStats: .init(calories: 2050, protein: 118, trained: false, hrv: "24", sleep: "5h 40m")
            )
        )
        context.insert(
            DailySummary(
                date: yesterday,
                summaryText: "Recovered with a solid protein day and a productive upper-body session.",
                keyStats: .init(calories: 2280, protein: 162, trained: true, hrv: "34", sleep: "7h 18m")
            )
        )
        context.insert(
            StoredMeal(
                date: calendar.date(byAdding: .hour, value: 8, to: today) ?? today,
                descriptionText: "Skyr bowl",
                calories: 430,
                protein: 32
            )
        )
        context.insert(
            StoredMeal(
                date: calendar.date(byAdding: .hour, value: 13, to: today) ?? today,
                descriptionText: "Chicken rice box",
                calories: 760,
                protein: 57
            )
        )
        context.insert(
            StoredWorkoutSet(
                date: calendar.date(byAdding: .hour, value: 18, to: today) ?? today,
                exercise: "Bench press",
                summary: "3x5 @ 100kg",
                notes: "Moved well"
            )
        )
        context.insert(
            StoredMetric(
                date: calendar.date(byAdding: .hour, value: 7, to: today) ?? today,
                type: "hrv",
                value: "33",
                context: "back toward baseline"
            )
        )
        context.insert(
            StoredMetric(
                date: calendar.date(byAdding: .hour, value: 7, to: today) ?? today,
                type: "sleep",
                value: "7h 12m",
                context: nil
            )
        )
        try context.save()
    }
}

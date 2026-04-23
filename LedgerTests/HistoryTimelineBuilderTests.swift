import Foundation
import XCTest
@testable import Ledger

final class HistoryTimelineBuilderTests: XCTestCase {
    func testBuildsWeeksInNewestFirstOrder() {
        let calendar = makeCalendar()
        let anchorDate = date("2026-04-22T12:00:00Z")

        let meals = [
            StoredMeal(date: date("2026-04-22T09:00:00Z"), descriptionText: "Chicken", calories: 300, protein: 50),
            StoredMeal(date: date("2026-04-20T09:00:00Z"), descriptionText: "Yogurt", calories: 200, protein: 20),
            StoredMeal(date: date("2026-04-20T12:00:00Z"), descriptionText: "Steak", calories: 500, protein: 40)
        ]
        let workouts = [
            StoredWorkoutSet(date: date("2026-04-22T18:00:00Z"), exercise: "Bench press", summary: "3x5 @ 100kg", notes: nil)
        ]
        let metrics = [
            StoredMetric(date: date("2026-04-22T07:00:00Z"), type: "sleep", value: "7h", context: nil),
            StoredMetric(date: date("2026-04-14T07:00:00Z"), type: "hrv", value: "32", context: nil)
        ]

        let weeks = HistoryTimelineBuilder.build(
            meals: meals,
            workoutSets: workouts,
            metrics: metrics,
            anchorDate: anchorDate,
            calendar: calendar
        )

        XCTAssertEqual(weeks.map(\.label), ["This week", "Last week"])
        XCTAssertEqual(weeks.first?.days.map(\.dayLabel), ["Wed", "Mon"])
        XCTAssertEqual(weeks.first?.days.first?.calories, 300)
        XCTAssertEqual(weeks.first?.days[1].protein, 60)
    }

    func testUsesDeterministicFallbackSummaryPriority() {
        let calendar = makeCalendar()
        let anchorDate = date("2026-04-22T12:00:00Z")

        let workoutDay = HistoryTimelineBuilder.build(
            meals: [
                StoredMeal(date: date("2026-04-22T09:00:00Z"), descriptionText: "Chicken", calories: 300, protein: 50)
            ],
            workoutSets: [
                StoredWorkoutSet(date: date("2026-04-22T18:00:00Z"), exercise: "Bench press", summary: "3x5 @ 100kg", notes: nil)
            ],
            metrics: [
                StoredMetric(date: date("2026-04-22T07:00:00Z"), type: "sleep", value: "7h", context: nil),
                StoredMetric(date: date("2026-04-22T06:00:00Z"), type: "mood", value: "good", context: nil)
            ],
            anchorDate: anchorDate,
            calendar: calendar
        )

        XCTAssertEqual(
            workoutDay.first?.days.first?.summary,
            "Bench press  3x5 @ 100kg · Sleep 7h"
        )

        let mealsOnly = HistoryTimelineBuilder.build(
            meals: [
                StoredMeal(date: date("2026-04-21T09:00:00Z"), descriptionText: "Eggs", calories: 200, protein: 20),
                StoredMeal(date: date("2026-04-21T12:00:00Z"), descriptionText: "Salmon", calories: 400, protein: 35)
            ],
            workoutSets: [],
            metrics: [],
            anchorDate: anchorDate,
            calendar: calendar
        )

        XCTAssertEqual(mealsOnly.first?.days.first?.summary, "2 meals, 55g protein")
    }

    func testReturnsEmptyWhenNoEntriesExist() {
        let weeks = HistoryTimelineBuilder.build(
            meals: [],
            workoutSets: [],
            metrics: [],
            anchorDate: Date(),
            calendar: makeCalendar()
        )

        XCTAssertTrue(weeks.isEmpty)
    }

    func testAttachesNarrativeProviderOutputToMatchingWeek() {
        let calendar = makeCalendar()
        let anchorDate = date("2026-04-22T12:00:00Z")

        let meals = [
            StoredMeal(date: date("2026-04-22T09:00:00Z"), descriptionText: "Chicken", calories: 300, protein: 50),
            StoredMeal(date: date("2026-04-14T09:00:00Z"), descriptionText: "Yogurt", calories: 200, protein: 20)
        ]

        let currentWeekStart = calendar.dateInterval(of: .weekOfYear, for: anchorDate)!.start
        let previousWeekStart = calendar.date(byAdding: .weekOfYear, value: -1, to: currentWeekStart)!

        var seenWeekStarts: [Date] = []
        let weeks = HistoryTimelineBuilder.build(
            meals: meals,
            workoutSets: [],
            metrics: [],
            anchorDate: anchorDate,
            calendar: calendar,
            narrativeProvider: { weekStart in
                seenWeekStarts.append(weekStart)
                if weekStart == currentWeekStart { return "this week narrative" }
                if weekStart == previousWeekStart { return "last week narrative" }
                return nil
            }
        )

        XCTAssertEqual(weeks.count, 2)
        XCTAssertEqual(weeks[0].narrative, "this week narrative")
        XCTAssertEqual(weeks[1].narrative, "last week narrative")
        XCTAssertEqual(Set(seenWeekStarts), Set([currentWeekStart, previousWeekStart]))
    }

    func testDefaultBuildHasNilNarrative() {
        let calendar = makeCalendar()
        let anchorDate = date("2026-04-22T12:00:00Z")
        let weeks = HistoryTimelineBuilder.build(
            meals: [
                StoredMeal(date: date("2026-04-22T09:00:00Z"), descriptionText: "Chicken", calories: 300, protein: 50)
            ],
            workoutSets: [],
            metrics: [],
            anchorDate: anchorDate,
            calendar: calendar
        )
        XCTAssertNil(weeks.first?.narrative)
    }

    private func makeCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ raw: String) -> Date {
        ISO8601DateFormatter().date(from: raw)!
    }
}

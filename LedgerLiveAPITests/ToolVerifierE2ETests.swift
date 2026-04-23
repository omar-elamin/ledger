import Foundation
import SwiftData
import XCTest
@testable import Ledger

@MainActor
final class ToolVerifierE2ETests: XCTestCase {

    func testScenarioEBlocksHallucinatedWorkoutWrite() async throws {
        try requireLiveAPI()

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt

        let baseDate = calendar.date(
            from: DateComponents(
                timeZone: calendar.timeZone,
                year: 2026, month: 4, day: 23, hour: 15, minute: 48
            )
        )!

        let container = try LedgerPersistentModels.makeContainer(inMemory: true)
        _ = try HistoryPreviewSeeder.seedIfNeeded(
            in: container,
            calendar: calendar,
            now: baseDate
        )

        var capturedLogs: [Data] = []
        let originalWriter = ToolCallVerifier.logWriter
        ToolCallVerifier.logWriter = { _, data in capturedLogs.append(data) }
        defer { ToolCallVerifier.logWriter = originalWriter }

        let context = ModelContext(container)

        let baselineWorkoutsToday = try fetchTodaysRows(StoredWorkoutSet.self, in: context, calendar: calendar, now: baseDate)
        let baselineMealsToday = try fetchTodaysRows(StoredMeal.self, in: context, calendar: calendar, now: baseDate)

        let viewModel = ChatViewModel(
            claudeClient: ClaudeClient(),
            calendar: calendar,
            now: { baseDate }
        )
        viewModel.loadInitialMessages(from: context)

        viewModel.send(
            "fucked up today. skipped the gym, ate shit all day, drank last night",
            modelContext: context
        )

        let deadline = Date().addingTimeInterval(60)
        while viewModel.isStreaming && Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertFalse(viewModel.isStreaming, "Stream did not complete within 60s")

        let workoutsAfter = try fetchTodaysRows(StoredWorkoutSet.self, in: context, calendar: calendar, now: baseDate)
        let mealsAfter = try fetchTodaysRows(StoredMeal.self, in: context, calendar: calendar, now: baseDate)

        XCTAssertEqual(workoutsAfter.count, baselineWorkoutsToday.count,
                       "No new workout should be written for a 'skipped the gym' message")
        XCTAssertEqual(mealsAfter.count, baselineMealsToday.count,
                       "No new meal should be written for a mood-only message")

        let coachReply = viewModel.messages.last?.content ?? ""
        XCTAssertFalse(coachReply.isEmpty, "Coach should still respond visibly")
        for prohibited in ["logged", "logging", "recording", "noted"] {
            XCTAssertFalse(coachReply.lowercased().contains(prohibited),
                           "Coach reply should not announce logging: \(coachReply)")
        }

        // If the LLM did attempt a write tool, the verifier should have blocked it.
        // If the LLM correctly fires no tools at all, there is no log entry — both outcomes are pass.
        for logData in capturedLogs {
            let line = String(data: logData, encoding: .utf8) ?? ""
            if line.contains("\"verdict\":\"blocked\"") {
                XCTAssertTrue(
                    line.contains("record_workout_set") || line.contains("update_meal_log"),
                    "Unexpected block on non-write tool: \(line)"
                )
            }
        }
    }

    private func fetchTodaysRows<T: PersistentModel>(
        _ type: T.Type,
        in context: ModelContext,
        calendar: Calendar,
        now: Date
    ) throws -> [T] {
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start

        let descriptor: FetchDescriptor<T>
        switch type {
        case is StoredWorkoutSet.Type:
            descriptor = FetchDescriptor<T>(
                predicate: #Predicate<T> { _ in true }
            )
        case is StoredMeal.Type:
            descriptor = FetchDescriptor<T>(
                predicate: #Predicate<T> { _ in true }
            )
        default:
            descriptor = FetchDescriptor<T>()
        }

        let all = try context.fetch(descriptor)
        return all.filter { model in
            if let workout = model as? StoredWorkoutSet {
                return workout.date >= start && workout.date < end
            }
            if let meal = model as? StoredMeal {
                return meal.date >= start && meal.date < end
            }
            return false
        }
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

import Foundation
import SwiftData
import XCTest
@testable import Ledger

@MainActor
final class HierarchicalMemoryPipelineTests: XCTestCase {
    func testChatWritesNightlyContextAndArchiveSearchStayConnected() async throws {
        let container = try TestHelpers.makeInMemoryContainer()
        let context = ModelContext(container)
        let calendar = TestHelpers.makeUTCCalendar()
        let clock = LedgerTestClock(
            initialDate: TestHelpers.makeDate(year: 2026, month: 4, day: 22, hour: 12, calendar: calendar),
            calendar: calendar
        )
        let client = StubStreamingClient(
            scripts: [
                .events([
                    .toolUseStart(id: "profile", name: "update_identity_fact"),
                    .toolUseDelta(id: "profile", partialJSON: #"{"key":"goal_weight","value":"78kg"}"#),
                    .toolUseEnd(id: "profile"),
                    .messageStop
                ]),
                .events([
                    .toolUseStart(id: "meal", name: "update_meal_log"),
                    .toolUseDelta(id: "meal", partialJSON: #"{"description":"Chicken rice box","estimated_calories":760,"estimated_protein_grams":57}"#),
                    .toolUseEnd(id: "meal"),
                    .messageStop
                ]),
                .events([.messageStop]),
                .events([
                    .toolUseStart(id: "archive", name: "search_archive"),
                    .toolUseDelta(id: "archive", partialJSON: #"{"query":"travel"}"#),
                    .toolUseEnd(id: "archive"),
                    .messageStop
                ])
            ]
        )
        let viewModel = ChatViewModel(
            claudeClient: client,
            calendar: calendar,
            now: { clock.now() }
        )
        viewModel.loadInitialMessages(from: context)

        viewModel.send("I want to cut to 78kg.", modelContext: context)
        await waitUntil { !viewModel.isStreaming }

        viewModel.send("Had chicken rice for lunch.", modelContext: context)
        await waitUntil { !viewModel.isStreaming }

        let memoryGenerator = ScriptedMemoryTextGenerator(scenario: .deterministic)
        let suiteName = "HierarchicalMemoryPipelineTests.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName) ?? .standard
        userDefaults.removePersistentDomain(forName: suiteName)
        let coordinator = MemoryMaintenanceCoordinator(
            maintainer: MemoryMaintainer(
                modelContainer: container,
                textGenerator: memoryGenerator,
                calendar: calendar,
                now: { clock.now() }
            ),
            textGenerator: memoryGenerator,
            userDefaults: userDefaults,
            calendar: calendar,
            now: { clock.now() }
        )

        _ = await coordinator.runNightlySequence(force: true, trigger: "test")

        viewModel.send("What do you know about me?", modelContext: context)
        await waitUntil { !viewModel.isStreaming }

        let invocations = await client.invocationsSnapshot()
        let contextInvocation = try XCTUnwrap(invocations.dropFirst(2).first)
        XCTAssertTrue(contextInvocation.contextBlock.contains("- goal_weight: 78kg"))
        XCTAssertTrue(contextInvocation.contextBlock.contains("## Recent days"))
        XCTAssertTrue(contextInvocation.contextBlock.contains("Hit 760 cal and 57g protein."))

        let oldWeekStart = TestHelpers.makeDate(year: 2026, month: 3, day: 9, calendar: calendar)
        context.insert(
            DailySummary(
                date: oldWeekStart,
                summaryText: "Travel week. Protein slipped and sleep was short.",
                keyStats: .init(calories: 2400, protein: 130, trained: false, hrv: "29", sleep: "6h 00m")
            )
        )
        context.insert(
            DailySummary(
                date: calendar.date(byAdding: .day, value: 1, to: oldWeekStart) ?? oldWeekStart,
                summaryText: "Travel continued and meals got loose.",
                keyStats: .init(calories: 2450, protein: 128, trained: false, hrv: "28", sleep: "5h 50m")
            )
        )
        try context.save()

        let rollupMaintainer = MemoryMaintainer(
            modelContainer: container,
            textGenerator: memoryGenerator,
            calendar: calendar,
            now: { clock.now() }
        )
        try await rollupMaintainer.rollupWeek()

        viewModel.send("How was last month?", modelContext: context)
        await waitUntil { !viewModel.isStreaming }

        let completedToolUses = await client.completedToolUsesSnapshot()
        let archiveResult = try XCTUnwrap(completedToolUses.first(where: { $0.id == "archive" }))
        XCTAssertTrue(archiveResult.content.contains("Travel week"))
        XCTAssertEqual(try context.fetch(FetchDescriptor<WeeklySummary>()).count, 1)
    }
}

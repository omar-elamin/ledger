import Foundation
import SwiftData
import XCTest
@testable import Ledger

@MainActor
final class ChatViewModelTests: XCTestCase {
    func testSeedsOpeningMessageOnlyOnce() throws {
        let container = try TestHelpers.makeInMemoryContainer()
        let context = ModelContext(container)
        let viewModel = ChatViewModel(
            claudeClient: StubStreamingClient(scripts: []),
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        viewModel.loadInitialMessages(from: context)
        viewModel.loadInitialMessages(from: context)

        XCTAssertEqual(viewModel.messages.count, 1)
        XCTAssertEqual(try TestHelpers.fetchMessages(from: context).count, 1)
        XCTAssertEqual(
            viewModel.messages.first?.content,
            "Hi. I'm here to help with your body — eating, training, sleep, all of it. What's going on with you?"
        )
    }

    func testAppendsMissingKeyFallback() async throws {
        let container = try TestHelpers.makeInMemoryContainer()
        let context = ModelContext(container)
        let client = StubStreamingClient(hasAPIKeyConfigured: false, scripts: [])
        let viewModel = ChatViewModel(claudeClient: client)
        viewModel.loadInitialMessages(from: context)

        viewModel.send("Hi", modelContext: context)
        await waitUntil {
            viewModel.messages.count == 3 && !viewModel.isStreaming
        }

        XCTAssertEqual(
            viewModel.messages.last?.content,
            "No API key configured. Add one to Ledger/Secrets.swift."
        )
        XCTAssertNil(viewModel.streamingMessage)
        XCTAssertEqual(try TestHelpers.fetchMessages(from: context).count, 3)
    }

    func testPersistsStreamedCoachReply() async throws {
        let container = try TestHelpers.makeInMemoryContainer()
        let context = ModelContext(container)
        let client = StubStreamingClient(
            scripts: [
                .events([
                    .textDelta("Hey"),
                    .textDelta(" there"),
                    .messageStop
                ])
            ]
        )
        let viewModel = ChatViewModel(claudeClient: client)
        viewModel.loadInitialMessages(from: context)

        viewModel.send("Hi", modelContext: context)
        await waitUntil {
            viewModel.messages.count == 3 && !viewModel.isStreaming
        }

        XCTAssertEqual(viewModel.messages.last?.content, "Hey there")
        XCTAssertNil(viewModel.streamingMessage)
        XCTAssertEqual(try TestHelpers.fetchMessages(from: context).last?.content, "Hey there")
    }

    func testPersistsStructuredToolOutputs() async throws {
        let container = try TestHelpers.makeInMemoryContainer()
        let context = ModelContext(container)
        let client = StubStreamingClient(
            scripts: [
                .events([
                    .toolUseStart(id: "meal", name: "update_meal_log"),
                    .toolUseDelta(id: "meal", partialJSON: #"{"description":"Chicken","estimated_calories":300,"estimated_protein_grams":50}"#),
                    .toolUseEnd(id: "meal"),
                    .toolUseStart(id: "workout", name: "record_workout_set"),
                    .toolUseDelta(id: "workout", partialJSON: #"{"exercise":"Bench press","summary":"3x5 @ 100kg","notes":"Moved well"}"#),
                    .toolUseEnd(id: "workout"),
                    .toolUseStart(id: "metric", name: "update_metric"),
                    .toolUseDelta(id: "metric", partialJSON: #"{"type":"sleep","value":"7h 10m","context":"solid"}"#),
                    .toolUseEnd(id: "metric"),
                    .toolUseStart(id: "profile", name: "update_profile"),
                    .toolUseDelta(id: "profile", partialJSON: #"{"key":"goal","value":"cut"}"#),
                    .toolUseEnd(id: "profile"),
                    .textDelta("Logged."),
                    .messageStop
                ])
            ]
        )
        let fixedNow = Date(timeIntervalSince1970: 1_700_000_100)
        let viewModel = ChatViewModel(
            claudeClient: client,
            now: { fixedNow }
        )
        viewModel.loadInitialMessages(from: context)

        viewModel.send("Log this", modelContext: context)
        await waitUntil {
            viewModel.messages.count == 3 && !viewModel.isStreaming
        }

        let meals = try TestHelpers.fetchAll(StoredMeal.self, from: context)
        let workouts = try TestHelpers.fetchAll(StoredWorkoutSet.self, from: context)
        let metrics = try TestHelpers.fetchAll(StoredMetric.self, from: context)
        let profiles = try TestHelpers.fetchAll(IdentityProfile.self, from: context)

        XCTAssertEqual(meals.count, 1)
        XCTAssertEqual(meals.first?.descriptionText, "Chicken")
        XCTAssertEqual(workouts.count, 1)
        XCTAssertEqual(workouts.first?.exercise, "Bench press")
        XCTAssertEqual(metrics.count, 1)
        XCTAssertEqual(metrics.first?.type, "sleep")
        XCTAssertEqual(profiles.count, 1)
        XCTAssertEqual(profiles.first?.scope, IdentityProfile.defaultScope)
        XCTAssertTrue(profiles.first?.markdownContent.contains("## Goals") == true)
        XCTAssertTrue(profiles.first?.markdownContent.contains("- goal: cut") == true)
        let completedToolUseCount = await client.completedToolUseCount()
        XCTAssertEqual(completedToolUseCount, 4)
    }

    func testUpsertsIdentityProfileAcrossSends() async throws {
        let container = try TestHelpers.makeInMemoryContainer()
        let context = ModelContext(container)
        let client = StubStreamingClient(
            scripts: [
                .events([
                    .toolUseStart(id: "profile-1", name: "update_profile"),
                    .toolUseDelta(id: "profile-1", partialJSON: #"{"key":"goal","value":"cut"}"#),
                    .toolUseEnd(id: "profile-1"),
                    .messageStop
                ]),
                .events([
                    .toolUseStart(id: "profile-2", name: "update_profile"),
                    .toolUseDelta(id: "profile-2", partialJSON: #"{"key":"goal","value":"maintain"}"#),
                    .toolUseEnd(id: "profile-2"),
                    .messageStop
                ])
            ]
        )
        let viewModel = ChatViewModel(claudeClient: client)
        viewModel.loadInitialMessages(from: context)

        viewModel.send("First", modelContext: context)
        await waitUntil {
            viewModel.messages.count == 2 && !viewModel.isStreaming
        }

        viewModel.send("Second", modelContext: context)
        await waitUntil {
            viewModel.messages.count == 3 && !viewModel.isStreaming
        }

        let profiles = try TestHelpers.fetchAll(IdentityProfile.self, from: context)
        XCTAssertEqual(profiles.count, 1)
        XCTAssertTrue(profiles.first?.markdownContent.contains("- goal: maintain") == true)
        XCTAssertFalse(profiles.first?.markdownContent.contains("- goal: cut") == true)
    }

    func testAppendsFallbackWhenStreamingFails() async throws {
        let container = try TestHelpers.makeInMemoryContainer()
        let context = ModelContext(container)
        let client = StubStreamingClient(scripts: [.error(TestError())])
        let viewModel = ChatViewModel(claudeClient: client)
        viewModel.loadInitialMessages(from: context)

        viewModel.send("Hi", modelContext: context)
        await waitUntil {
            viewModel.messages.count == 3 && !viewModel.isStreaming
        }

        XCTAssertEqual(
            viewModel.messages.last?.content,
            "Something went wrong on my end — try again in a moment."
        )
        XCTAssertNil(viewModel.streamingMessage)
    }

    func testBuildsAndPassesHierarchicalContextBlock() async throws {
        let container = try TestHelpers.makeInMemoryContainer()
        let context = ModelContext(container)
        let now = Date(timeIntervalSince1970: 1_710_000_000)
        context.insert(
            IdentityProfile(
                scope: IdentityProfile.defaultScope,
                markdownContent: "## Goals\n- goal: cut",
                lastUpdated: now
            )
        )
        context.insert(
            Pattern(
                key: "protein_social_days",
                descriptionText: "Protein tends to lag on social days.",
                evidenceNote: "Seen across three recent weekends.",
                confidence: .medium,
                firstObserved: now.addingTimeInterval(-10_000),
                lastReinforced: now
            )
        )
        context.insert(
            ActiveStateSnapshot(
                scope: ActiveStateSnapshot.defaultScope,
                markdownContent: "Current weight is stable. Bench is moving.",
                generatedAt: now
            )
        )
        context.insert(
            DailySummary(
                date: Calendar.current.startOfDay(for: now.addingTimeInterval(-86_400)),
                summaryText: "Quiet day. Ate enough and slept well.",
                keyStats: .init(calories: 2200, protein: 150, trained: false, hrv: "34", sleep: "7h 20m")
            )
        )
        try context.save()

        let client = StubStreamingClient(
            scripts: [
                .events([
                    .messageStop
                ])
            ]
        )
        let viewModel = ChatViewModel(
            claudeClient: client,
            calendar: .current,
            now: { now }
        )
        viewModel.loadInitialMessages(from: context)

        viewModel.send("Hi", modelContext: context)
        await waitUntil {
            !viewModel.isStreaming
        }

        let invocations = await client.invocationsSnapshot()
        let invocation = try XCTUnwrap(invocations.first)
        XCTAssertTrue(invocation.contextBlock.contains("## Who this person is"))
        XCTAssertTrue(invocation.contextBlock.contains("## Patterns observed"))
        XCTAssertTrue(invocation.contextBlock.contains("## Where they are right now"))
        XCTAssertTrue(invocation.contextBlock.contains("## Recent days"))
        XCTAssertTrue(invocation.contextBlock.contains("## Today so far"))
        XCTAssertTrue(invocation.contextBlock.contains("- goal: cut"))
    }

    func testSearchArchiveToolReturnsMatchesWithoutMutatingArchive() async throws {
        let container = try TestHelpers.makeInMemoryContainer()
        let context = ModelContext(container)
        let now = Date(timeIntervalSince1970: 1_710_000_000)
        context.insert(
            WeeklySummary(
                startDate: Calendar.current.startOfDay(for: now.addingTimeInterval(-21 * 86_400)),
                endDate: Calendar.current.startOfDay(for: now.addingTimeInterval(-15 * 86_400)),
                summaryText: "Travel week. Protein slipped and sleep was short after late nights.",
                keyStats: .init(calories: 2400, protein: 130, trained: false, hrv: "29", sleep: "6h 00m")
            )
        )
        try context.save()

        let client = StubStreamingClient(
            scripts: [
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
            now: { now }
        )
        viewModel.loadInitialMessages(from: context)

        viewModel.send("How was last month?", modelContext: context)
        await waitUntil {
            !viewModel.isStreaming
        }

        let completedToolUses = await client.completedToolUsesSnapshot()
        let archiveToolUse = try XCTUnwrap(completedToolUses.first(where: { $0.id == "archive" }))
        XCTAssertTrue(archiveToolUse.content.contains("Travel week"))
        XCTAssertEqual(try TestHelpers.fetchAll(WeeklySummary.self, from: context).count, 1)
        XCTAssertEqual(try TestHelpers.fetchAll(StoredMeal.self, from: context).count, 0)
    }
}

import Foundation
import SwiftData
import XCTest
@testable import Ledger

@MainActor
final class ChatViewModelTests: XCTestCase {
    private var originalLogWriter: ((URL, Data) throws -> Void)!

    override func setUp() {
        super.setUp()
        originalLogWriter = ToolCallVerifier.logWriter
        ToolCallVerifier.logWriter = { _, _ in }
    }

    override func tearDown() {
        ToolCallVerifier.logWriter = originalLogWriter
        super.tearDown()
    }

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
            "Hi. What should I call you?"
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

    func testShowsTransientThinkingStatusWhileWaitingForFirstVisibleOutput() async throws {
        let container = try TestHelpers.makeInMemoryContainer()
        let context = ModelContext(container)
        let client = StubStreamingClient(
            scripts: [
                .delayedEvents(
                    [.messageStop],
                    initialDelayNanoseconds: 200_000_000,
                    eventDelayNanoseconds: 0
                )
            ]
        )
        let viewModel = ChatViewModel(claudeClient: client)
        viewModel.loadInitialMessages(from: context)

        viewModel.send("Hi", modelContext: context)
        await waitUntil {
            viewModel.isStreaming && viewModel.activityStatus == "Thinking..."
        }

        XCTAssertEqual(try TestHelpers.fetchMessages(from: context).map(\.content), [
            "Hi. What should I call you?",
            "Hi"
        ])

        await waitUntil {
            !viewModel.isStreaming
        }

        XCTAssertNil(viewModel.activityStatus)
        XCTAssertEqual(try TestHelpers.fetchMessages(from: context).map(\.content), [
            "Hi. What should I call you?",
            "Hi"
        ])
    }

    func testShowsWriteToolStatusThenClearsOnVisibleText() async throws {
        let container = try TestHelpers.makeInMemoryContainer()
        let context = ModelContext(container)
        let client = StubStreamingClient(
            scripts: [
                .delayedEvents(
                    [
                        .toolUseStart(id: "meal", name: "update_meal_log"),
                        .toolUseDelta(
                            id: "meal",
                            partialJSON: #"{"description":"Chicken","estimated_calories":300,"estimated_protein_grams":50,"evidence":"Log this chicken"}"#
                        ),
                        .toolUseEnd(id: "meal"),
                        .textDelta("Logged."),
                        .messageStop
                    ],
                    initialDelayNanoseconds: 100_000_000,
                    eventDelayNanoseconds: 200_000_000
                )
            ]
        )
        let viewModel = ChatViewModel(claudeClient: client)
        viewModel.loadInitialMessages(from: context)

        viewModel.send("Log this chicken", modelContext: context)
        await waitUntil {
            viewModel.activityStatus == "Thinking..."
        }
        await waitUntil {
            viewModel.activityStatus == "Writing that down..."
        }
        await waitUntil {
            viewModel.activityStatus == "Thinking..."
        }
        await waitUntil {
            viewModel.activityStatus == nil && viewModel.streamingMessage?.content == "Logged."
        }
        await waitUntil {
            !viewModel.isStreaming
        }

        XCTAssertEqual(viewModel.messages.last?.content, "Logged.")
        XCTAssertFalse(try TestHelpers.fetchMessages(from: context).contains { storedMessage in
            ["Thinking...", "Writing that down..."].contains(storedMessage.content)
        })
    }

    func testShowsMemoryStatusForArchiveSearch() async throws {
        let container = try TestHelpers.makeInMemoryContainer()
        let context = ModelContext(container)
        let client = StubStreamingClient(
            scripts: [
                .delayedEvents(
                    [
                        .toolUseStart(id: "archive", name: "search_archive"),
                        .toolUseDelta(id: "archive", partialJSON: #"{"query":"travel"}"#),
                        .toolUseEnd(id: "archive"),
                        .textDelta("I checked."),
                        .messageStop
                    ],
                    initialDelayNanoseconds: 100_000_000,
                    eventDelayNanoseconds: 200_000_000
                )
            ]
        )
        let viewModel = ChatViewModel(claudeClient: client)
        viewModel.loadInitialMessages(from: context)

        viewModel.send("How was travel?", modelContext: context)
        await waitUntil {
            viewModel.activityStatus == "Checking memory..."
        }
        await waitUntil {
            viewModel.activityStatus == "Thinking..."
        }
        await waitUntil {
            !viewModel.isStreaming
        }

        XCTAssertNil(viewModel.activityStatus)
        XCTAssertEqual(viewModel.messages.last?.content, "I checked.")
    }

    func testPersistsStructuredToolOutputs() async throws {
        let container = try TestHelpers.makeInMemoryContainer()
        let context = ModelContext(container)
        let client = StubStreamingClient(
            scripts: [
                .events([
                    .toolUseStart(id: "meal", name: "update_meal_log"),
                    .toolUseDelta(id: "meal", partialJSON: #"{"description":"Chicken","estimated_calories":300,"estimated_protein_grams":50,"evidence":"log this"}"#),
                    .toolUseEnd(id: "meal"),
                    .toolUseStart(id: "workout", name: "record_workout_set"),
                    .toolUseDelta(id: "workout", partialJSON: #"{"exercise":"Bench press","summary":"3x5 @ 100kg","notes":"Moved well","evidence":"log this"}"#),
                    .toolUseEnd(id: "workout"),
                    .toolUseStart(id: "metric", name: "update_metric"),
                    .toolUseDelta(id: "metric", partialJSON: #"{"type":"sleep","value":"7h 10m","context":"solid","evidence":"log this"}"#),
                    .toolUseEnd(id: "metric"),
                    .toolUseStart(id: "profile", name: "update_identity_fact"),
                    .toolUseDelta(id: "profile", partialJSON: #"{"key":"goal","value":"cut","evidence":"log this"}"#),
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
                    .toolUseStart(id: "profile-1", name: "update_identity_fact"),
                    .toolUseDelta(id: "profile-1", partialJSON: #"{"key":"goal","value":"cut","evidence":"first"}"#),
                    .toolUseEnd(id: "profile-1"),
                    .messageStop
                ]),
                .events([
                    .toolUseStart(id: "profile-2", name: "update_identity_fact"),
                    .toolUseDelta(id: "profile-2", partialJSON: #"{"key":"goal","value":"maintain","evidence":"second"}"#),
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

    func testPrefixesOutgoingMessagesWithTimestamps() async throws {
        let container = try TestHelpers.makeInMemoryContainer()
        let context = ModelContext(container)
        let client = StubStreamingClient(
            scripts: [.events([.textDelta("ok"), .messageStop])]
        )
        let viewModel = ChatViewModel(
            claudeClient: client,
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
        viewModel.loadInitialMessages(from: context)

        viewModel.send("hello", modelContext: context)
        await waitUntil {
            viewModel.messages.count == 3 && !viewModel.isStreaming
        }

        let invocations = await client.invocationsSnapshot()
        let invocation = try XCTUnwrap(invocations.first)
        XCTAssertFalse(invocation.messages.isEmpty)
        for message in invocation.messages {
            XCTAssertTrue(
                message.content.hasPrefix("["),
                "expected timestamp prefix, got \(message.content)"
            )
            XCTAssertTrue(
                message.content.contains("] "),
                "expected '] ' after timestamp, got \(message.content)"
            )
        }

        let userMessage = try XCTUnwrap(invocation.messages.last)
        XCTAssertTrue(
            userMessage.content.hasSuffix("hello"),
            "user content should follow the prefix, got \(userMessage.content)"
        )

        // Stored content stays plain for the chat UI — prefix is LLM-only.
        let stored = try TestHelpers.fetchMessages(from: context)
        XCTAssertTrue(
            stored.contains(where: { $0.content == "hello" }),
            "expected the original 'hello' content in storage without a timestamp prefix"
        )
    }

    func testStripsEchoedTimestampPrefixFromCoachReply() async throws {
        let container = try TestHelpers.makeInMemoryContainer()
        let context = ModelContext(container)
        let client = StubStreamingClient(
            scripts: [.events([.textDelta("[Apr 23, 21:16] Got it."), .messageStop])]
        )
        let viewModel = ChatViewModel(
            claudeClient: client,
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
        viewModel.loadInitialMessages(from: context)

        viewModel.send("hello", modelContext: context)
        await waitUntil {
            viewModel.messages.count == 3 && !viewModel.isStreaming
        }

        XCTAssertEqual(viewModel.messages.last?.content, "Got it.")
        let stored = try TestHelpers.fetchMessages(from: context)
        XCTAssertTrue(
            stored.contains(where: { $0.content == "Got it." }),
            "expected timestamp prefix stripped from stored coach message"
        )
        XCTAssertFalse(
            stored.contains(where: { $0.content.hasPrefix("[Apr") }),
            "no stored coach message should keep the echoed timestamp"
        )
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

    func testVerifierBlocksHallucinatedWorkoutAndSkipsWrite() async throws {
        var capturedLogs: [Data] = []
        ToolCallVerifier.logWriter = { _, data in capturedLogs.append(data) }

        let container = try TestHelpers.makeInMemoryContainer()
        let context = ModelContext(container)
        let client = StubStreamingClient(
            scripts: [
                .events([
                    .toolUseStart(id: "workout", name: "record_workout_set"),
                    .toolUseDelta(id: "workout", partialJSON: #"{"exercise":"Bench press","summary":"4×6 @ 80kg","notes":"First time at 80kg since restart"}"#),
                    .toolUseEnd(id: "workout"),
                    .textDelta("Tough one."),
                    .messageStop
                ])
            ]
        )
        let viewModel = ChatViewModel(claudeClient: client)
        viewModel.loadInitialMessages(from: context)

        viewModel.send(
            "fucked up today. skipped the gym, ate shit all day, drank last night",
            modelContext: context
        )
        await waitUntil {
            !viewModel.isStreaming
        }

        let workouts = try TestHelpers.fetchAll(StoredWorkoutSet.self, from: context)
        XCTAssertEqual(workouts.count, 0, "Hallucinated workout write must be blocked")

        let completedToolUses = await client.completedToolUsesSnapshot()
        let workoutToolUse = try XCTUnwrap(completedToolUses.first(where: { $0.id == "workout" }))
        XCTAssertEqual(workoutToolUse.content, "OK")
        XCTAssertFalse(workoutToolUse.isError)

        XCTAssertEqual(capturedLogs.count, 1)
        let logLine = try XCTUnwrap(String(data: capturedLogs[0], encoding: .utf8))
        XCTAssertTrue(logLine.contains("\"verdict\":\"blocked\""))
        XCTAssertTrue(logLine.contains("\"toolName\":\"record_workout_set\""))
    }
}

import Foundation
import SwiftData

struct LedgerAppEnvironment {
    let modelContainer: ModelContainer
    let memoryMaintenanceScheduler: MemoryMaintenanceScheduler
    let makeChatViewModel: @MainActor () -> ChatViewModel
    let makeDayAnchorController: @MainActor () -> DayAnchorController
    let makeTestHarness: @MainActor () -> LedgerTestHarness?
    let shouldRegisterBackgroundTasks: Bool
    let shouldAutoRunMaintenance: Bool

    static func bootstrap(processInfo: ProcessInfo = .processInfo) -> LedgerAppEnvironment {
        let launchConfiguration = LedgerLaunchConfiguration(processInfo: processInfo)
        let calendar = launchConfiguration.calendar
        let modelContainer = Self.makeModelContainer(storeURL: launchConfiguration.storeURL)
        let now = launchConfiguration.nowProvider
        Self.runDevelopmentSeedIfNeeded(
            seed: launchConfiguration.developmentSeed,
            in: modelContainer,
            calendar: calendar,
            now: now()
        )
        let streamingClient: any CoachStreamingClient
        let memoryTextGenerator: any MemoryTextGeneratingClient

        if let scenario = launchConfiguration.coachScenario {
            streamingClient = ScriptedCoachClient(scenario: scenario)
            memoryTextGenerator = ScriptedMemoryTextGenerator(
                scenario: launchConfiguration.memoryScenario ?? .deterministic
            )
        } else {
            let claudeClient = ClaudeClient()
            streamingClient = claudeClient
            memoryTextGenerator = claudeClient
        }

        let maintainer = MemoryMaintainer(
            modelContainer: modelContainer,
            textGenerator: memoryTextGenerator,
            calendar: calendar,
            now: now
        )
        let memoryCoordinator = MemoryMaintenanceCoordinator(
            maintainer: maintainer,
            textGenerator: memoryTextGenerator,
            userDefaults: launchConfiguration.userDefaults,
            calendar: calendar,
            now: now
        )
        let memoryScheduler = MemoryMaintenanceScheduler(
            coordinator: memoryCoordinator,
            calendar: calendar,
            now: now
        )
        return LedgerAppEnvironment(
            modelContainer: modelContainer,
            memoryMaintenanceScheduler: memoryScheduler,
            makeChatViewModel: {
                ChatViewModel(
                    claudeClient: streamingClient,
                    calendar: calendar,
                    now: now
                )
            },
            makeDayAnchorController: {
                DayAnchorController(
                    notificationCenter: .default,
                    calendar: calendar,
                    now: now
                )
            },
            makeTestHarness: {
                launchConfiguration.testClock.map { clock in
                    LedgerTestHarness(
                        modelContainer: modelContainer,
                        coordinator: memoryCoordinator,
                        userDefaults: launchConfiguration.userDefaults,
                        calendar: calendar,
                        clock: clock,
                        snapshotURL: launchConfiguration.snapshotURL
                    )
                }
            },
            shouldRegisterBackgroundTasks: launchConfiguration.shouldRegisterBackgroundTasks,
            shouldAutoRunMaintenance: launchConfiguration.shouldAutoRunMaintenance
        )
    }

    private static func makeModelContainer(storeURL: URL?) -> ModelContainer {
        do {
            if let storeURL {
                try FileManager.default.createDirectory(
                    at: storeURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true,
                    attributes: nil
                )
                return try LedgerPersistentModels.makeContainer(url: storeURL)
            }

            return try LedgerPersistentModels.makeContainer()
        } catch {
            fatalError("Failed to create model container: \(error)")
        }
    }

    private static func runDevelopmentSeedIfNeeded(
        seed: LedgerDevelopmentSeed?,
        in modelContainer: ModelContainer,
        calendar: Calendar,
        now: Date
    ) {
        guard let seed else { return }

        do {
            switch seed {
            case .historyPreview:
                let didSeed = try HistoryPreviewSeeder.seedIfNeeded(
                    in: modelContainer,
                    calendar: calendar,
                    now: now
                )
                if didSeed {
                    print("Seeded history preview data into the local store.")
                }
            }
        } catch {
            print("Failed to seed development data: \(error)")
        }
    }
}

private struct LedgerLaunchConfiguration {
    let coachScenario: LedgerTestCoachScenario?
    let memoryScenario: LedgerTestMemoryScenario?
    let developmentSeed: LedgerDevelopmentSeed?
    let storeURL: URL?
    let userDefaults: UserDefaults
    let testClock: LedgerTestClock?
    let nowProvider: @Sendable () -> Date
    let snapshotURL: URL?
    let shouldRegisterBackgroundTasks: Bool
    let shouldAutoRunMaintenance: Bool
    let calendar: Calendar

    init(processInfo: ProcessInfo) {
        let environment = processInfo.environment
        let isUITestMode = environment["LEDGER_TEST_MODE"] == "1"
        let isHostedUnitTest = !isUITestMode && Self.isHostedUnitTestEnvironment(environment)
        var resolvedStoreURL: URL? = environment["LEDGER_TEST_STORE_PATH"].flatMap {
            guard !$0.isEmpty else { return nil }
            return URL(fileURLWithPath: $0)
        }
        let resolvedSnapshotURL: URL? = environment["LEDGER_TEST_SNAPSHOT_PATH"].flatMap {
            guard !$0.isEmpty else { return nil }
            return URL(fileURLWithPath: $0)
        }
        self.coachScenario = isUITestMode
            ? LedgerTestCoachScenario(
                rawValue: environment["LEDGER_TEST_COACH_SCENARIO"]
                    ?? environment["LEDGER_TEST_SCENARIO"]
                    ?? ""
            ) ?? .happyPath
            : nil
        self.memoryScenario = isUITestMode
            ? LedgerTestMemoryScenario(rawValue: environment["LEDGER_TEST_MEMORY_SCENARIO"] ?? "") ?? .deterministic
            : nil
        self.developmentSeed = LedgerDevelopmentSeed(
            rawValue: environment["LEDGER_DEV_SEED_PRESET"] ?? ""
        )
        self.snapshotURL = resolvedSnapshotURL
        self.shouldRegisterBackgroundTasks = !isUITestMode && !isHostedUnitTest
        self.shouldAutoRunMaintenance = (!isUITestMode && !isHostedUnitTest)
            || environment["LEDGER_TEST_AUTO_MAINTENANCE"] == "1"
        let resolvedCalendar: Calendar
        if isUITestMode {
            var fixedCalendar = Calendar(identifier: .gregorian)
            fixedCalendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
            resolvedCalendar = fixedCalendar
        } else {
            resolvedCalendar = .autoupdatingCurrent
        }
        self.calendar = resolvedCalendar

        if isUITestMode {
            guard resolvedStoreURL != nil else {
                fatalError("LEDGER_TEST_STORE_PATH is required in test mode.")
            }
            guard
                let suiteName = environment["LEDGER_TEST_DEFAULTS_SUITE"],
                !suiteName.isEmpty,
                let userDefaults = UserDefaults(suiteName: suiteName)
            else {
                fatalError("LEDGER_TEST_DEFAULTS_SUITE is required in test mode.")
            }

            let fixedDate = Self.parseFixedDate(environment["LEDGER_TEST_NOW_ISO8601"]) ?? Date()
            let testClock = LedgerTestClock(
                initialDate: fixedDate,
                calendar: resolvedCalendar
            )
            self.userDefaults = userDefaults
            self.testClock = testClock
            self.nowProvider = { testClock.now() }
        } else if isHostedUnitTest {
            guard
                let suiteName = Self.makeHostedTestDefaultsSuite(processInfo: processInfo),
                let userDefaults = UserDefaults(suiteName: suiteName)
            else {
                fatalError("Failed to create isolated hosted-test defaults.")
            }

            resolvedStoreURL = Self.makeHostedTestStoreURL(processInfo: processInfo)
            self.userDefaults = userDefaults
            self.testClock = nil
            self.nowProvider = { Date() }
        } else {
            self.userDefaults = .standard
            self.testClock = nil
            self.nowProvider = { Date() }
        }
        self.storeURL = resolvedStoreURL
    }

    private static func parseFixedDate(_ rawValue: String?) -> Date? {
        guard let rawValue, !rawValue.isEmpty else {
            return nil
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: rawValue) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: rawValue)
    }

    private static func isHostedUnitTestEnvironment(_ environment: [String: String]) -> Bool {
        [
            "XCTestBundlePath",
            "XCTestConfigurationFilePath",
            "XCInjectBundleInto"
        ].contains { key in
            guard let value = environment[key] else { return false }
            return !value.isEmpty
        }
    }

    private static func makeHostedTestStoreURL(processInfo: ProcessInfo) -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LedgerHostedTests", isDirectory: true)
            .appendingPathComponent(processInfo.globallyUniqueString, isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        return directory.appendingPathComponent("ledger.store")
    }

    private static func makeHostedTestDefaultsSuite(processInfo: ProcessInfo) -> String? {
        "com.omarelamin.ledger.hosted-tests.\(processInfo.globallyUniqueString)"
    }
}

private actor ScriptedCoachClient: CoachStreamingClient {
    nonisolated let hasAPIKeyConfigured = true

    private let scenario: LedgerTestCoachScenario
    private var waitingToolResults: [String: CheckedContinuation<Void, Never>] = [:]
    private var completedToolResults: Set<String> = []
    private var toolResultContent: [String: String] = [:]

    init(scenario: LedgerTestCoachScenario) {
        self.scenario = scenario
    }

    func streamMessage(
        messages: [Message],
        contextBlock: String,
        tools: [Tool]
    ) async -> AsyncThrowingStream<StreamEvent, Error> {
        let latestUserText = messages.last(where: { $0.role == .user })?.content.lowercased() ?? ""
        let scenario = self.scenario

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    switch scenario {
                    case .happyPath:
                        if latestUserText.contains("factor meals") || latestUserText.contains("chicken") {
                            try await self.runMealLoggingScenario(into: continuation)
                        } else if latestUserText.contains("bench") || latestUserText.contains("@") {
                            try await self.runWorkoutLoggingScenario(into: continuation)
                        } else if latestUserText.contains("hrv") || latestUserText.contains("sleep") || latestUserText.contains("weight") {
                            try await self.runMetricLoggingScenario(latestUserText: latestUserText, into: continuation)
                        } else if latestUserText.contains("cut to") || latestUserText.contains("goal weight") {
                            try await self.runProfileUpdateScenario(latestUserText: latestUserText, into: continuation)
                        } else if latestUserText.contains("last month") || latestUserText.contains("archive") || latestUserText.contains("how was") {
                            try await self.runArchiveScenario(into: continuation)
                        } else if latestUserText.contains("what do you know about me") {
                            try await self.runIdentityRecallScenario(contextBlock: contextBlock, into: continuation)
                        } else if latestUserText.contains("pattern") {
                            try await self.runPatternRecallScenario(contextBlock: contextBlock, into: continuation)
                        } else {
                            try await self.runPlainReplyScenario(into: continuation)
                        }
                    case .failingRequest:
                        throw ClaudeClientError.apiError("Scripted request failure.")
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func completeToolUse(id: String, content: String, isError: Bool) async {
        toolResultContent[id] = content
        if let continuation = waitingToolResults.removeValue(forKey: id) {
            continuation.resume()
        } else {
            completedToolResults.insert(id)
        }
    }

    private func runPlainReplyScenario(
        into continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) async throws {
        for chunk in Self.textChunks(
            "You're here. Good. Tell me what's actually going on."
        ) {
            continuation.yield(.textDelta(chunk))
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        continuation.yield(.messageStop)
    }

    private func runWorkoutLoggingScenario(
        into continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) async throws {
        let toolID = "ui-test-workout-log"
        continuation.yield(.toolUseStart(id: toolID, name: "record_workout_set"))
        continuation.yield(
            .toolUseDelta(
                id: toolID,
                partialJSON: #"{"exercise":"Bench press","summary":"3x5 @ 100kg","notes":"Moved well"}"#
            )
        )
        continuation.yield(.toolUseEnd(id: toolID))
        await waitForToolResult(id: toolID)

        for chunk in Self.textChunks("Logged the bench work. Keep the next set of numbers clean.") {
            continuation.yield(.textDelta(chunk))
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        continuation.yield(.messageStop)
    }

    private func runMetricLoggingScenario(
        latestUserText: String,
        into continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) async throws {
        let toolID = "ui-test-metric-log"
        let payload: String

        if latestUserText.contains("sleep") {
            payload = #"{"type":"sleep","value":"7h 10m","context":"steady"}"#
        } else if latestUserText.contains("weight") {
            payload = #"{"type":"weight","value":"81.8kg","context":"morning"}"#
        } else {
            payload = #"{"type":"hrv","value":"24","context":"low after drinks"}"#
        }

        continuation.yield(.toolUseStart(id: toolID, name: "update_metric"))
        continuation.yield(.toolUseDelta(id: toolID, partialJSON: payload))
        continuation.yield(.toolUseEnd(id: toolID))
        await waitForToolResult(id: toolID)

        for chunk in Self.textChunks("Metric is in. Treat it like signal, not decoration.") {
            continuation.yield(.textDelta(chunk))
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        continuation.yield(.messageStop)
    }

    private func runProfileUpdateScenario(
        latestUserText: String,
        into continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) async throws {
        let toolID = "ui-test-profile-log"
        let value = latestUserText.contains("78") ? "78kg" : "80kg"
        continuation.yield(.toolUseStart(id: toolID, name: "update_profile"))
        continuation.yield(
            .toolUseDelta(
                id: toolID,
                partialJSON: #"{"key":"goal_weight","value":"\#(value)"}"#
            )
        )
        continuation.yield(.toolUseEnd(id: toolID))
        await waitForToolResult(id: toolID)

        for chunk in Self.textChunks("Noted. That's the number the work needs to move toward.") {
            continuation.yield(.textDelta(chunk))
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        continuation.yield(.messageStop)
    }

    private func runArchiveScenario(
        into continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) async throws {
        let toolID = "ui-test-archive"
        continuation.yield(.toolUseStart(id: toolID, name: "search_archive"))
        continuation.yield(.toolUseDelta(id: toolID, partialJSON: #"{"query":"travel"}"#))
        continuation.yield(.toolUseEnd(id: toolID))
        await waitForToolResult(id: toolID)

        let archiveResult = toolResultContent[toolID] ?? "No archive matches."
        let summaryLine = archiveResult
            .components(separatedBy: .newlines)
            .first?
            .replacingOccurrences(of: "- ", with: "")
            ?? archiveResult

        for chunk in Self.textChunks("Last month in one line: \(summaryLine)") {
            continuation.yield(.textDelta(chunk))
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        continuation.yield(.messageStop)
    }

    private func runIdentityRecallScenario(
        contextBlock: String,
        into continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) async throws {
        let line = contextBlock
            .components(separatedBy: .newlines)
            .first(where: { $0.contains("goal_weight") })
            ?? "I don't have anything stable on you yet."

        for chunk in Self.textChunks(line.replacingOccurrences(of: "- ", with: "")) {
            continuation.yield(.textDelta(chunk))
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        continuation.yield(.messageStop)
    }

    private func runPatternRecallScenario(
        contextBlock: String,
        into continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) async throws {
        let line = contextBlock
            .components(separatedBy: .newlines)
            .first(where: { $0.lowercased().contains("protein tends to lag on social days") })
            ?? "No stable pattern is showing yet."

        for chunk in Self.textChunks(line.replacingOccurrences(of: "- [medium] ", with: "")) {
            continuation.yield(.textDelta(chunk))
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        continuation.yield(.messageStop)
    }

    private func runMealLoggingScenario(
        into continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) async throws {
        let toolID = "ui-test-meal-log"
        continuation.yield(.toolUseStart(id: toolID, name: "update_meal_log"))
        continuation.yield(
            .toolUseDelta(
                id: toolID,
                partialJSON: #"{"description":"2 Factor meals + 200g chicken","estimated_calories":1200,"estimated_protein_grams":110}"#
            )
        )
        continuation.yield(.toolUseEnd(id: toolID))
        await waitForToolResult(id: toolID)

        for chunk in Self.textChunks(
            "Solid. That's roughly 1,200 cal and ~110g protein in the tank. Good protein floor for the day.\n\nThat gives you room later. Keep the rest of the day tight."
        ) {
            continuation.yield(.textDelta(chunk))
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        continuation.yield(.messageStop)
    }

    private func waitForToolResult(id: String) async {
        if completedToolResults.remove(id) != nil {
            return
        }

        await withCheckedContinuation { continuation in
            waitingToolResults[id] = continuation
        }
    }

    private static func textChunks(_ text: String) -> [String] {
        var chunks: [String] = []
        var current = ""

        for character in text {
            current.append(character)
            if character == " " || character == "\n" {
                chunks.append(current)
                current = ""
            }
        }

        if !current.isEmpty {
            chunks.append(current)
        }

        return chunks
    }
}

import Foundation
import SwiftData

struct LedgerAppEnvironment {
    let modelContainer: ModelContainer
    let memoryMaintenanceScheduler: MemoryMaintenanceScheduler
    let makeChatViewModel: @MainActor () -> ChatViewModel
    let makeDayAnchorController: @MainActor () -> DayAnchorController

    static func bootstrap(processInfo: ProcessInfo = .processInfo) -> LedgerAppEnvironment {
        let launchConfiguration = LedgerLaunchConfiguration(processInfo: processInfo)
        let calendar = Calendar.autoupdatingCurrent
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

        if let scenario = launchConfiguration.testScenario {
            streamingClient = ScriptedCoachClient(scenario: scenario)
            memoryTextGenerator = DisabledMemoryTextGenerator()
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
            }
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
    let testScenario: LedgerUITestScenario?
    let developmentSeed: LedgerDevelopmentSeed?
    let storeURL: URL?
    let nowProvider: @Sendable () -> Date

    init(processInfo: ProcessInfo) {
        let environment = processInfo.environment
        let isUITestMode = environment["LEDGER_TEST_MODE"] == "1"
        self.testScenario = isUITestMode
            ? LedgerUITestScenario(rawValue: environment["LEDGER_TEST_SCENARIO"] ?? "") ?? .happyPath
            : nil
        self.developmentSeed = LedgerDevelopmentSeed(
            rawValue: environment["LEDGER_DEV_SEED_PRESET"] ?? ""
        )
        self.storeURL = environment["LEDGER_TEST_STORE_PATH"].flatMap {
            guard !$0.isEmpty else { return nil }
            return URL(fileURLWithPath: $0)
        }

        if let fixedDate = Self.parseFixedDate(environment["LEDGER_TEST_NOW_ISO8601"]) {
            self.nowProvider = { fixedDate }
        } else {
            self.nowProvider = { Date() }
        }
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
}

private enum LedgerUITestScenario: String {
    case happyPath = "happy_path"
    case failingRequest = "failing_request"
}

private actor ScriptedCoachClient: CoachStreamingClient {
    nonisolated let hasAPIKeyConfigured = true

    private let scenario: LedgerUITestScenario
    private var waitingToolResults: [String: CheckedContinuation<Void, Never>] = [:]
    private var completedToolResults: Set<String> = []

    init(scenario: LedgerUITestScenario) {
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

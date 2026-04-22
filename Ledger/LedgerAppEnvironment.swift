import Foundation
import SwiftData

struct LedgerAppEnvironment {
    let modelContainer: ModelContainer
    let makeChatViewModel: @MainActor () -> ChatViewModel
    let makeDayAnchorController: @MainActor () -> DayAnchorController

    static func bootstrap(processInfo: ProcessInfo = .processInfo) -> LedgerAppEnvironment {
        let launchConfiguration = LedgerLaunchConfiguration(processInfo: processInfo)
        let calendar = Calendar.autoupdatingCurrent
        let modelContainer = Self.makeModelContainer(storeURL: launchConfiguration.storeURL)
        let now = launchConfiguration.nowProvider
        let streamingClient: any CoachStreamingClient = launchConfiguration.testScenario.map {
            ScriptedCoachClient(scenario: $0)
        } ?? ClaudeClient()

        return LedgerAppEnvironment(
            modelContainer: modelContainer,
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
}

private struct LedgerLaunchConfiguration {
    let testScenario: LedgerUITestScenario?
    let storeURL: URL?
    let nowProvider: @Sendable () -> Date

    init(processInfo: ProcessInfo) {
        let environment = processInfo.environment
        let isUITestMode = environment["LEDGER_TEST_MODE"] == "1"
        self.testScenario = isUITestMode
            ? LedgerUITestScenario(rawValue: environment["LEDGER_TEST_SCENARIO"] ?? "") ?? .happyPath
            : nil
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
        profile: String,
        todayLog: DayLog?,
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
            "You're here. Good. What are we actually solving today?"
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
            "Solid. That's roughly 1,200 cal and ~110g protein in the tank. Good protein floor for the day.\n\nWhat's the plan from here - training today, another meal, or just checking in?"
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

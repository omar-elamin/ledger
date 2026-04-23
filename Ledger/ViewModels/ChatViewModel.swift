import Foundation
import Observation
import SwiftData
import SwiftUI

@MainActor
@Observable
final class ChatViewModel {
    var messages: [Message] = []
    var isStreaming = false
    var streamingMessage: Message?
    var activityStatus: String?

    private let claudeClient: any CoachStreamingClient
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    private var hasLoadedInitialMessages = false
    private var pendingToolNames: [String: String] = [:]
    private var pendingToolJSON: [String: String] = [:]
    private var pendingUserMessage: String?
    private var activeSendTask: Task<Void, Never>?

    init(
        claudeClient: any CoachStreamingClient = ClaudeClient(),
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.claudeClient = claudeClient
        self.calendar = calendar
        self.now = now
    }

    func loadInitialMessages(from modelContext: ModelContext) {
        guard !hasLoadedInitialMessages else { return }
        hasLoadedInitialMessages = true

        do {
            let descriptor = FetchDescriptor<StoredMessage>(
                sortBy: [SortDescriptor(\.timestamp, order: .forward)]
            )
            let storedMessages = try modelContext.fetch(descriptor)

            if storedMessages.isEmpty {
                // Keep this seeded opener in sync with CoachPrompt.firstConversationSection.
                let openingMessage = Message(
                    role: .coach,
                    content: CoachPrompt.firstConversationOpener,
                    timestamp: now()
                )
                modelContext.insert(StoredMessage(message: openingMessage))
                try modelContext.save()
                messages = [openingMessage]
            } else {
                messages = storedMessages.map(Message.init)
            }
        } catch {
            print("Failed to load initial messages: \(error)")
        }
    }

    func send(_ text: String, modelContext: ModelContext) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty, !isStreaming else { return }

        activeSendTask?.cancel()
        activeSendTask = Task { @MainActor [weak self] in
            await self?.runSend(trimmedText, modelContext: modelContext)
        }
    }

    private func runSend(_ text: String, modelContext: ModelContext) async {
        pendingUserMessage = text
        let userMessage = Message(role: .user, content: text, timestamp: now())
        persistAndAppend(userMessage, in: modelContext)

        guard claudeClient.hasAPIKeyConfigured else {
            appendCoachFallback(
                "No API key configured. Add one to Ledger/Secrets.swift.",
                modelContext: modelContext
            )
            return
        }

        let contextBlock = ContextBuilder(
            modelContext: modelContext,
            calendar: calendar,
            now: now
        )
        .buildChatContext()

        isStreaming = true
        pendingToolNames.removeAll()
        pendingToolJSON.removeAll()
        withAnimation(.smooth(duration: 0.3)) {
            streamingMessage = Message(role: .coach, content: "", timestamp: now())
            activityStatus = ChatActivityStatus.thinking
        }

        do {
            let stream = await claudeClient.streamMessage(
                messages: messages.map(Self.timestampPrefixed),
                contextBlock: contextBlock,
                tools: CoachTools.all
            )

            for try await event in stream {
                await handleStreamEvent(event, modelContext: modelContext)
            }
        } catch is CancellationError {
            clearStreamingState()
        } catch {
            print("Claude streaming failed: \(error)")
            clearStreamingState()
            appendCoachFallback(
                "Something went wrong on my end — try again in a moment.",
                modelContext: modelContext
            )
        }
    }

    private func handleStreamEvent(_ event: StreamEvent, modelContext: ModelContext) async {
        switch event {
        case .textDelta(let delta):
            guard !delta.isEmpty else { return }
            activityStatus = nil
            if streamingMessage == nil {
                streamingMessage = Message(role: .coach, content: delta, timestamp: now())
            } else {
                streamingMessage?.content += delta
            }
            if let current = streamingMessage?.content {
                streamingMessage?.content = Self.stripTimestampPrefix(current)
            }
        case .toolUseStart(let id, let name):
            pendingToolNames[id] = name
            pendingToolJSON[id] = ""
            activityStatus = ChatActivityStatus.status(forToolName: name)
        case .toolUseDelta(let id, let partialJSON):
            pendingToolJSON[id, default: ""] += partialJSON
        case .toolUseEnd(let id):
            await handleCompletedToolUse(id: id, modelContext: modelContext)
        case .messageStop:
            finishStreamingMessage(in: modelContext)
        }
    }

    private func handleCompletedToolUse(id: String, modelContext: ModelContext) async {
        guard let toolName = pendingToolNames.removeValue(forKey: id) else {
            await claudeClient.completeToolUse(
                id: id,
                content: "Tool metadata was missing.",
                isError: true
            )
            activityStatus = ChatActivityStatus.thinking
            pendingToolJSON.removeValue(forKey: id)
            return
        }

        let rawJSON = pendingToolJSON.removeValue(forKey: id) ?? ""

        do {
            let resultMessage = try persistToolUse(
                name: toolName,
                rawJSON: rawJSON,
                modelContext: modelContext
            )
            await claudeClient.completeToolUse(id: id, content: resultMessage, isError: false)
            activityStatus = ChatActivityStatus.thinking
        } catch {
            print("Failed to persist tool use \(toolName): \(error)")
            await claudeClient.completeToolUse(
                id: id,
                content: "Failed to persist \(toolName).",
                isError: true
            )
            activityStatus = ChatActivityStatus.thinking
        }
    }

    private func persistToolUse(
        name: String,
        rawJSON: String,
        modelContext: ModelContext
    ) throws -> String {
        let verdict = ToolCallVerifier.verify(
            toolName: name,
            rawJSON: rawJSON,
            userMessage: pendingUserMessage
        )

        switch verdict {
        case .allow:
            break
        case .flag(let reason):
            ToolCallVerifier.appendLog(
                toolName: name,
                rawJSON: rawJSON,
                userMessage: pendingUserMessage ?? "",
                verdict: "flagged",
                reason: reason
            )
        case .block(let reason):
            ToolCallVerifier.appendLog(
                toolName: name,
                rawJSON: rawJSON,
                userMessage: pendingUserMessage ?? "",
                verdict: "blocked",
                reason: reason
            )
            return "OK"
        }

        let data = Data(rawJSON.utf8)
        let decoder = JSONDecoder()

        switch name {
        case "update_meal_log":
            let payload = try decoder.decode(UpdateMealLogPayload.self, from: data)
            modelContext.insert(
                StoredMeal(
                    date: now(),
                    descriptionText: payload.description,
                    calories: payload.estimatedCalories,
                    protein: payload.estimatedProteinGrams
                )
            )
            try modelContext.save()
            return "Meal logged."
        case "record_workout_set":
            let payload = try decoder.decode(RecordWorkoutSetPayload.self, from: data)
            modelContext.insert(
                StoredWorkoutSet(
                    date: now(),
                    exercise: payload.exercise,
                    summary: payload.summary,
                    notes: payload.notes
                )
            )
            try modelContext.save()
            return "Workout logged."
        case "update_metric":
            let payload = try decoder.decode(UpdateMetricPayload.self, from: data)
            modelContext.insert(
                StoredMetric(
                    date: now(),
                    type: payload.type,
                    value: payload.value,
                    context: payload.context
                )
            )
            try modelContext.save()
            return "Metric logged."
        case "update_identity_fact":
            let payload = try decoder.decode(UpdateProfilePayload.self, from: data)
            try upsertProfileEntry(payload, in: modelContext)
            return "Identity fact stored."
        case "search_archive":
            let payload = try decoder.decode(SearchArchivePayload.self, from: data)
            return try ContextBuilder(
                modelContext: modelContext,
                calendar: calendar,
                now: now
            )
            .archiveSearchMarkdown(query: payload.query)
        default:
            throw ClaudeClientError.apiError("Unsupported tool \(name)")
        }
    }

    private func upsertProfileEntry(_ payload: UpdateProfilePayload, in modelContext: ModelContext) throws {
        var descriptor = FetchDescriptor<IdentityProfile>(
            predicate: #Predicate { profile in
                profile.scope == "default"
            }
        )
        descriptor.fetchLimit = 1

        if let existing = try modelContext.fetch(descriptor).first {
            existing.markdownContent = IdentityProfileDocument.upserting(
                key: payload.key,
                value: payload.value,
                into: existing.markdownContent
            )
            existing.lastUpdated = now()
        } else {
            modelContext.insert(
                IdentityProfile(
                    scope: IdentityProfile.defaultScope,
                    markdownContent: IdentityProfileDocument.upserting(
                        key: payload.key,
                        value: payload.value,
                        into: ""
                    ),
                    lastUpdated: now()
                )
            )
        }

        try modelContext.save()
    }

    private func finishStreamingMessage(in modelContext: ModelContext) {
        defer {
            pendingToolNames.removeAll()
            pendingToolJSON.removeAll()
            activityStatus = nil
            isStreaming = false
        }

        guard var streamingMessage, !streamingMessage.content.isEmpty else {
            self.streamingMessage = nil
            return
        }

        streamingMessage.content = Self.stripTimestampPrefix(streamingMessage.content)
        guard !streamingMessage.content.isEmpty else {
            self.streamingMessage = nil
            return
        }

        do {
            modelContext.insert(StoredMessage(message: streamingMessage))
            try modelContext.save()
        } catch {
            print("Failed to persist coach message: \(error)")
        }

        withAnimation(.smooth(duration: 0.35)) {
            messages.append(streamingMessage)
            self.streamingMessage = nil
        }
    }

    private func clearStreamingState() {
        withAnimation(.smooth(duration: 0.2)) {
            streamingMessage = nil
            activityStatus = nil
        }
        pendingToolNames.removeAll()
        pendingToolJSON.removeAll()
        pendingUserMessage = nil
        isStreaming = false
    }

    private func appendCoachFallback(_ text: String, modelContext: ModelContext) {
        let message = Message(role: .coach, content: text, timestamp: now())
        persistAndAppend(message, in: modelContext)
    }

    // Stored messages stay plain; the prefix is only context for the model.
    private static func timestampPrefixed(_ message: Message) -> Message {
        var copy = message
        copy.content = "[\(messageTimestampFormatter.string(from: message.timestamp))] \(message.content)"
        return copy
    }

    // The model occasionally echoes the injected `[MMM d, HH:mm]` prefix at the
    // start of its own reply. Keep the prefix out of whatever the user sees.
    private static func stripTimestampPrefix(_ content: String) -> String {
        guard let match = content.firstMatch(of: timestampPrefixRegex), match.range.lowerBound == content.startIndex else {
            return content
        }
        return String(content[match.range.upperBound...])
    }

    private static let timestampPrefixRegex = /\A\[[A-Z][a-z]{2} \d{1,2}, \d{1,2}:\d{2}\]\s*/

    private static let messageTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = .autoupdatingCurrent
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "MMM d, HH:mm"
        return formatter
    }()

    private func persistAndAppend(_ message: Message, in modelContext: ModelContext) {
        do {
            modelContext.insert(StoredMessage(message: message))
            try modelContext.save()
        } catch {
            print("Failed to persist message: \(error)")
        }

        withAnimation(.smooth(duration: 0.3)) {
            messages.append(message)
        }
    }
}

private enum ChatActivityStatus {
    static let thinking = "Thinking..."
    static let writing = "Writing that down..."
    static let checkingMemory = "Checking memory..."

    static func status(forToolName toolName: String) -> String {
        switch toolName {
        case "search_archive":
            return checkingMemory
        case "update_meal_log", "record_workout_set", "update_metric", "update_identity_fact":
            return writing
        default:
            return thinking
        }
    }
}

private struct UpdateMealLogPayload: Decodable {
    let description: String
    let estimatedCalories: Int
    let estimatedProteinGrams: Int

    enum CodingKeys: String, CodingKey {
        case description
        case estimatedCalories = "estimated_calories"
        case estimatedProteinGrams = "estimated_protein_grams"
    }
}

private struct RecordWorkoutSetPayload: Decodable {
    let exercise: String
    let summary: String
    let notes: String?
}

private struct UpdateMetricPayload: Decodable {
    let type: String
    let value: String
    let context: String?
}

private struct UpdateProfilePayload: Decodable {
    let key: String
    let value: String
}

private struct SearchArchivePayload: Decodable {
    let query: String
}

private extension StoredMessage {
    convenience init(message: Message) {
        self.init(
            id: message.id,
            role: message.role.rawValue,
            content: message.content,
            timestamp: message.timestamp
        )
    }
}

private extension Message {
    init(_ storedMessage: StoredMessage) {
        self.init(
            id: storedMessage.id,
            role: storedMessage.role == MessageRole.user.rawValue ? .user : .coach,
            content: storedMessage.content,
            timestamp: storedMessage.timestamp
        )
    }
}

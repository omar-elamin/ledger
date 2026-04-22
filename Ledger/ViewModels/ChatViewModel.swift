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

    private let claudeClient: any CoachStreamingClient
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    private var hasLoadedInitialMessages = false
    private var pendingToolNames: [String: String] = [:]
    private var pendingToolJSON: [String: String] = [:]
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
                let openingMessage = Message(
                    role: .coach,
                    content: "Hi. I'm here to help with your body — eating, training, sleep, all of it. What's going on with you?",
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
        let userMessage = Message(role: .user, content: text, timestamp: now())
        persistAndAppend(userMessage, in: modelContext)

        guard claudeClient.hasAPIKeyConfigured else {
            appendCoachFallback(
                "No API key configured. Add one to Ledger/Secrets.swift.",
                modelContext: modelContext
            )
            return
        }

        let profile = fetchProfileString(from: modelContext)
        let todayLog = fetchTodayLog(from: modelContext)

        isStreaming = true
        pendingToolNames.removeAll()
        pendingToolJSON.removeAll()
        withAnimation(.smooth(duration: 0.3)) {
            streamingMessage = Message(role: .coach, content: "", timestamp: now())
        }

        do {
            let stream = await claudeClient.streamMessage(
                messages: messages,
                profile: profile,
                todayLog: todayLog,
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
            if streamingMessage == nil {
                streamingMessage = Message(role: .coach, content: delta, timestamp: now())
            } else {
                streamingMessage?.content += delta
            }
        case .toolUseStart(let id, let name):
            pendingToolNames[id] = name
            pendingToolJSON[id] = ""
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
        } catch {
            print("Failed to persist tool use \(toolName): \(error)")
            await claudeClient.completeToolUse(
                id: id,
                content: "Failed to persist \(toolName).",
                isError: true
            )
        }
    }

    private func persistToolUse(
        name: String,
        rawJSON: String,
        modelContext: ModelContext
    ) throws -> String {
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
        case "update_profile":
            let payload = try decoder.decode(UpdateProfilePayload.self, from: data)
            try upsertProfileEntry(payload, in: modelContext)
            return "Profile updated."
        default:
            throw ClaudeClientError.apiError("Unsupported tool \(name)")
        }
    }

    private func upsertProfileEntry(_ payload: UpdateProfilePayload, in modelContext: ModelContext) throws {
        let key = payload.key
        var descriptor = FetchDescriptor<ProfileEntry>(
            predicate: #Predicate { entry in
                entry.key == key
            }
        )
        descriptor.fetchLimit = 1

        if let existing = try modelContext.fetch(descriptor).first {
            existing.value = payload.value
            existing.updatedAt = now()
        } else {
            modelContext.insert(ProfileEntry(key: payload.key, value: payload.value, updatedAt: now()))
        }

        try modelContext.save()
    }

    private func finishStreamingMessage(in modelContext: ModelContext) {
        defer {
            pendingToolNames.removeAll()
            pendingToolJSON.removeAll()
            isStreaming = false
        }

        guard let streamingMessage, !streamingMessage.content.isEmpty else {
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
        }
        pendingToolNames.removeAll()
        pendingToolJSON.removeAll()
        isStreaming = false
    }

    private func appendCoachFallback(_ text: String, modelContext: ModelContext) {
        let message = Message(role: .coach, content: text, timestamp: now())
        persistAndAppend(message, in: modelContext)
    }

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

    private func fetchProfileString(from modelContext: ModelContext) -> String {
        do {
            let descriptor = FetchDescriptor<ProfileEntry>(
                sortBy: [SortDescriptor(\.updatedAt, order: .forward)]
            )
            let entries = try modelContext.fetch(descriptor)

            guard !entries.isEmpty else {
                return "No saved profile yet."
            }

            return entries
                .map { "\($0.key): \($0.value)" }
                .joined(separator: "\n")
        } catch {
            print("Failed to fetch profile entries: \(error)")
            return "No saved profile yet."
        }
    }

    private func fetchTodayLog(from modelContext: ModelContext) -> DayLog? {
        let bounds = dayBounds(for: now())
        let start = bounds.start
        let end = bounds.end

        do {
            let meals = try modelContext.fetch(
                FetchDescriptor<StoredMeal>(
                    predicate: #Predicate {
                        $0.date >= start && $0.date < end
                    },
                    sortBy: [SortDescriptor(\.date, order: .forward)]
                )
            )
            let workouts = try modelContext.fetch(
                FetchDescriptor<StoredWorkoutSet>(
                    predicate: #Predicate {
                        $0.date >= start && $0.date < end
                    },
                    sortBy: [SortDescriptor(\.date, order: .forward)]
                )
            )
            let metrics = try modelContext.fetch(
                FetchDescriptor<StoredMetric>(
                    predicate: #Predicate {
                        $0.date >= start && $0.date < end
                    },
                    sortBy: [SortDescriptor(\.date, order: .forward)]
                )
            )

            guard !meals.isEmpty || !workouts.isEmpty || !metrics.isEmpty else {
                return nil
            }

            return DayLog(
                date: now(),
                calories: meals.reduce(0) { $0 + $1.calories },
                protein: meals.reduce(0) { $0 + $1.protein },
                eaten: meals.map(Self.mealLine),
                trained: workouts.map(Self.workoutLine),
                body: metrics.map(Self.metricLine),
                summary: ""
            )
        } catch {
            print("Failed to fetch today's log: \(error)")
            return nil
        }
    }

    private static func mealLine(_ meal: StoredMeal) -> String {
        "\(meal.descriptionText) (~\(meal.calories) cal, \(meal.protein)g protein)"
    }

    private static func workoutLine(_ workout: StoredWorkoutSet) -> String {
        if let notes = workout.notes, !notes.isEmpty {
            return "\(workout.exercise)  \(workout.summary)  \(notes)"
        }
        return "\(workout.exercise)  \(workout.summary)"
    }

    private static func metricLine(_ metric: StoredMetric) -> String {
        let type: String
        switch metric.type.lowercased() {
        case "hrv":
            type = "HRV"
        case "sleep":
            type = "Sleep"
        case "weight":
            type = "Weight"
        case "mood":
            type = "Mood"
        default:
            type = metric.type.capitalized
        }

        if let context = metric.context, !context.isEmpty {
            return "\(type) \(metric.value) \(context)"
        }
        return "\(type) \(metric.value)"
    }

    private func dayBounds(for date: Date) -> (start: Date, end: Date) {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        return (start, end)
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

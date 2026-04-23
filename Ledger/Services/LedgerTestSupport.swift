import Foundation
import Observation
import SwiftData

final class LedgerTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    private let calendar: Calendar

    init(initialDate: Date, calendar: Calendar) {
        self.value = initialDate
        self.calendar = calendar
    }

    func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set(_ date: Date) {
        lock.lock()
        value = date
        lock.unlock()
    }

    func advanceDays(_ count: Int) {
        lock.lock()
        value = calendar.date(byAdding: .day, value: count, to: value) ?? value
        lock.unlock()
    }
}

enum LedgerTestCoachScenario: String {
    case happyPath = "happy_path"
    case failingRequest = "failing_request"
}

enum LedgerTestMemoryScenario: String {
    case deterministic = "deterministic"
    case failing = "failing"
}

@MainActor
@Observable
final class LedgerTestHarness {
    var statusMessage = "idle"

    private let modelContainer: ModelContainer
    private let coordinator: MemoryMaintenanceCoordinator
    private let userDefaults: UserDefaults
    private let calendar: Calendar
    private let clock: LedgerTestClock
    private let snapshotURL: URL?

    init(
        modelContainer: ModelContainer,
        coordinator: MemoryMaintenanceCoordinator,
        userDefaults: UserDefaults,
        calendar: Calendar,
        clock: LedgerTestClock,
        snapshotURL: URL?
    ) {
        self.modelContainer = modelContainer
        self.coordinator = coordinator
        self.userDefaults = userDefaults
        self.calendar = calendar
        self.clock = clock
        self.snapshotURL = snapshotURL
    }

    func setNow(_ iso8601: String) {
        statusMessage = "time:setting"
        guard let date = Self.iso8601.date(from: iso8601) else {
            statusMessage = "time:error"
            return
        }

        clock.set(date)
        statusMessage = "time:set"
    }

    func advanceDays(_ count: Int) {
        statusMessage = "time:advancing"
        clock.advanceDays(count)
        statusMessage = "time:advanced"
    }

    func runNightly(force: Bool) async {
        statusMessage = "nightly:running"
        let success = await coordinator.runNightlySequence(force: force, trigger: "test-harness")
        statusMessage = success ? "nightly:success" : "nightly:failure"
    }

    func resetMaintenanceTimestamps() {
        statusMessage = "timestamps:resetting"
        userDefaults.removeObject(forKey: MemoryMaintenanceCoordinator.nightlyRunKey)
        userDefaults.removeObject(forKey: MemoryMaintenanceCoordinator.weeklyRunKey)
        statusMessage = "timestamps:reset"
    }

    func dumpMemorySnapshot() {
        statusMessage = "snapshot:running"
        guard let snapshotURL else {
            statusMessage = "snapshot:error"
            return
        }

        do {
            try FileManager.default.createDirectory(
                at: snapshotURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )

            let snapshot = try MemorySnapshot.capture(
                modelContainer: modelContainer,
                calendar: calendar,
                now: clock.now(),
                lastNightlyRunAt: userDefaults.object(forKey: MemoryMaintenanceCoordinator.nightlyRunKey) as? Date,
                lastWeeklyRunAt: userDefaults.object(forKey: MemoryMaintenanceCoordinator.weeklyRunKey) as? Date
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(snapshot)
            try data.write(to: snapshotURL, options: .atomic)
            statusMessage = "snapshot:success"
        } catch {
            statusMessage = "snapshot:error"
        }
    }

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

struct MemorySnapshot: Codable, Equatable {
    let nowISO8601: String
    let lastNightlyRunISO8601: String?
    let lastWeeklyRunISO8601: String?
    let identityProfile: IdentityProfileSnapshot?
    let patterns: [MemoryPatternSnapshot]
    let activeStateSnapshot: ActiveStateSnapshotValue?
    let dailySummaries: [SummarySnapshotValue]
    let weeklySummaries: [ArchiveSummarySnapshot]
    let monthlySummaries: [ArchiveSummarySnapshot]

    static func capture(
        modelContainer: ModelContainer,
        calendar: Calendar,
        now: Date,
        lastNightlyRunAt: Date?,
        lastWeeklyRunAt: Date?
    ) throws -> MemorySnapshot {
        let context = ModelContext(modelContainer)

        let identityProfile = try context.fetch(
            FetchDescriptor<IdentityProfile>(
                predicate: #Predicate { $0.scope == "default" }
            )
        ).first

        let patterns = try context.fetch(
            FetchDescriptor<Pattern>(
                sortBy: [SortDescriptor(\.lastReinforced, order: .forward)]
            )
        )

        let activeState = try context.fetch(
            FetchDescriptor<ActiveStateSnapshot>(
                predicate: #Predicate { $0.scope == "default" }
            )
        ).first

        let daily = try context.fetch(
            FetchDescriptor<DailySummary>(
                sortBy: [SortDescriptor(\.date, order: .forward)]
            )
        )
        let weekly = try context.fetch(
            FetchDescriptor<WeeklySummary>(
                sortBy: [SortDescriptor(\.startDate, order: .forward)]
            )
        )
        let monthly = try context.fetch(
            FetchDescriptor<MonthlySummary>(
                sortBy: [SortDescriptor(\.startDate, order: .forward)]
            )
        )

        return MemorySnapshot(
            nowISO8601: Self.timestampFormatter.string(from: now),
            lastNightlyRunISO8601: lastNightlyRunAt.map(Self.timestampFormatter.string(from:)),
            lastWeeklyRunISO8601: lastWeeklyRunAt.map(Self.timestampFormatter.string(from:)),
            identityProfile: identityProfile.map {
                IdentityProfileSnapshot(
                    markdownContent: $0.markdownContent,
                    sections: IdentityProfileDocument.sections(from: $0.markdownContent),
                    lastUpdatedISO8601: Self.timestampFormatter.string(from: $0.lastUpdated)
                )
            },
            patterns: patterns.map {
                MemoryPatternSnapshot(
                    key: $0.key,
                    descriptionText: $0.descriptionText,
                    evidenceNote: $0.evidenceNote,
                    confidence: $0.confidence.rawValue,
                    firstObserved: Self.dayFormatter.string(from: calendar.startOfDay(for: $0.firstObserved)),
                    lastReinforced: Self.dayFormatter.string(from: calendar.startOfDay(for: $0.lastReinforced))
                )
            },
            activeStateSnapshot: activeState.map {
                ActiveStateSnapshotValue(
                    markdownContent: $0.markdownContent,
                    generatedAtISO8601: Self.timestampFormatter.string(from: $0.generatedAt)
                )
            },
            dailySummaries: daily.map {
                SummarySnapshotValue(
                    startDate: Self.dayFormatter.string(from: $0.date),
                    endDate: Self.dayFormatter.string(from: $0.date),
                    summaryText: $0.summaryText,
                    keyStats: $0.keyStats
                )
            },
            weeklySummaries: weekly.map {
                ArchiveSummarySnapshot(
                    startDate: Self.dayFormatter.string(from: $0.startDate),
                    endDate: Self.dayFormatter.string(from: $0.endDate),
                    summaryText: $0.summaryText,
                    keyStats: $0.keyStats
                )
            },
            monthlySummaries: monthly.map {
                ArchiveSummarySnapshot(
                    startDate: Self.dayFormatter.string(from: $0.startDate),
                    endDate: Self.dayFormatter.string(from: $0.endDate),
                    summaryText: $0.summaryText,
                    keyStats: $0.keyStats
                )
            }
        )
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()
}

struct IdentityProfileSnapshot: Codable, Equatable {
    let markdownContent: String
    let sections: [String: [String: String]]
    let lastUpdatedISO8601: String
}

struct MemoryPatternSnapshot: Codable, Equatable {
    let key: String
    let descriptionText: String
    let evidenceNote: String
    let confidence: String
    let firstObserved: String
    let lastReinforced: String
}

struct ActiveStateSnapshotValue: Codable, Equatable {
    let markdownContent: String
    let generatedAtISO8601: String
}

struct SummarySnapshotValue: Codable, Equatable {
    let startDate: String
    let endDate: String
    let summaryText: String
    let keyStats: SummaryKeyStats
}

struct ArchiveSummarySnapshot: Codable, Equatable {
    let startDate: String
    let endDate: String
    let summaryText: String
    let keyStats: SummaryKeyStats
}

actor ScriptedMemoryTextGenerator: MemoryTextGeneratingClient {
    nonisolated let hasAPIKeyConfigured = true

    private let scenario: LedgerTestMemoryScenario

    init(scenario: LedgerTestMemoryScenario) {
        self.scenario = scenario
    }

    func generateText(
        systemPrompt: String,
        userPrompt: String,
        maxTokens: Int
    ) async throws -> String {
        switch scenario {
        case .failing:
            throw ClaudeClientError.apiError("Scripted memory generation failure.")
        case .deterministic:
            break
        }

        switch systemPrompt {
        case MemoryMaintainer.activeStateSystemPrompt:
            let input = try Self.decode(ActiveStateInput.self, from: userPrompt)
            return Self.renderActiveState(input)
        case MemoryMaintainer.dailySummarySystemPrompt:
            let input = try Self.decode(DailySummaryInput.self, from: userPrompt)
            return Self.renderDailySummary(input)
        case MemoryMaintainer.patternsSystemPrompt:
            let input = try Self.decode(PatternsInput.self, from: userPrompt)
            return try Self.renderPatterns(input)
        case MemoryMaintainer.identityUpdateSystemPrompt:
            let input = try Self.decode(IdentityInput.self, from: userPrompt)
            return try Self.renderIdentityUpdates(input)
        case MemoryMaintainer.archiveRollupSystemPrompt:
            let input = try Self.decode(ArchiveRollupInput.self, from: userPrompt)
            return Self.renderArchiveRollup(input)
        default:
            throw ClaudeClientError.apiError("Unsupported scripted memory prompt.")
        }
    }

    private static func renderActiveState(_ input: ActiveStateInput) -> String {
        let averages = averages(from: input.dailyStats)
        let metrics = input.latestMetrics
            .map { "- \($0.type): \($0.value)\($0.context.map { " (\($0))" } ?? "")" }
            .joined(separator: "\n")
        let weights = input.workingWeights
            .map { "- \($0.exercise): \($0.loadText) (\($0.summary))" }
            .joined(separator: "\n")

        let metricsSection = metrics.isEmpty ? "- No recovery metrics logged." : metrics
        let weightsSection = weights.isEmpty ? "- No working weights logged." : weights

        return """
        ### Current window
        - Window: \(input.windowStart) → \(input.windowEnd)
        - Average intake: \(averages.calories) cal, \(averages.protein)g protein
        - Training streak: \(input.trainingStreakDays)d
        - Logging streak: \(input.loggingStreakDays)d

        ### Latest metrics
        \(metricsSection)

        ### Working weights
        \(weightsSection)
        """
    }

    private static func renderDailySummary(_ input: DailySummaryInput) -> String {
        let combined = ([input.todayMarkdown] + input.messages.map(\.content)).joined(separator: " ").lowercased()
        let socialContext = combined.contains("social") || combined.contains("friends") || combined.contains("drank") || combined.contains("drinks")
        let travelContext = combined.contains("travel")
        let factor = combined.contains("factor")
        let chicken = combined.contains("chicken")
        let bench = combined.contains("bench")

        var sentences: [String] = [
            "Hit \(input.keyStats.calories) cal and \(input.keyStats.protein)g protein."
        ]

        if factor || chicken {
            sentences.append("Meals stayed simple and protein-forward.")
        }

        if bench || input.keyStats.trained {
            sentences.append("Training got logged and the day kept some structure.")
        }

        if socialContext {
            if input.keyStats.protein < 130 {
                sentences.append("It was a social day and protein still ran light.")
            } else {
                sentences.append("It was a social day and protein held up better than usual.")
            }
        }

        if travelContext {
            sentences.append("Travel pulled the day off its usual structure.")
        }

        if let hrv = input.keyStats.hrv {
            sentences.append("HRV landed at \(hrv).")
        }

        if let sleep = input.keyStats.sleep {
            sentences.append("Sleep was \(sleep).")
        }

        return sentences.joined(separator: " ")
    }

    private static func renderPatterns(_ input: PatternsInput) throws -> String {
        let matching = input.summaries.filter {
            let text = $0.summaryText.lowercased()
            return (text.contains("social") || text.contains("friends") || text.contains("drank"))
                && $0.keyStats.protein < 130
        }

        let hasExisting = input.currentPatterns.contains(where: { $0.key == "protein_social_days" })
        var operations: [[String: String]] = []

        if matching.count >= 2 {
            let action = hasExisting ? "update" : "add"
            let confidence = matching.count >= 3 ? "medium" : "low"
            operations.append([
                "action": action,
                "key": "protein_social_days",
                "description": "Protein tends to lag on social days.",
                "evidenceNote": "Repeated across recent social days with protein under 130g.",
                "confidence": confidence,
                "firstObserved": matching.first?.date ?? "",
                "lastReinforced": matching.last?.date ?? ""
            ])
        } else if hasExisting {
            operations.append([
                "action": "remove",
                "key": "protein_social_days",
                "evidenceNote": "The recent window does not reinforce it."
            ])
        }

        let body = ["operations": operations]
        let data = try JSONSerialization.data(withJSONObject: body, options: [.prettyPrinted, .sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    private static func renderIdentityUpdates(_ input: IdentityInput) throws -> String {
        let currentFacts = IdentityProfileDocument.facts(from: input.currentIdentityMarkdown)
        var proposals: [[String: String]] = []

        for summary in input.summaries {
            let text = summary.summaryText.lowercased()
            if let match = text.range(of: #"cut to (\d+(?:\.\d+)?)kg"#, options: .regularExpression) {
                let raw = String(text[match]).replacingOccurrences(of: "cut to ", with: "")
                if currentFacts["goal_weight"] != raw {
                    proposals.append([
                        "kind": "factual",
                        "confidence": "high",
                        "key": "goal_weight",
                        "value": raw,
                        "rationale": "The recent summaries state this goal directly."
                    ])
                }
                break
            }
        }

        let body = ["proposals": proposals]
        let data = try JSONSerialization.data(withJSONObject: body, options: [.prettyPrinted, .sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    private static func renderArchiveRollup(_ input: ArchiveRollupInput) -> String {
        let themes = input.entries
            .map(\.summaryText)
            .prefix(2)
            .joined(separator: " ")
        return "From \(input.startDate) to \(input.endDate), average intake ran \(input.aggregateStats.calories) cal and \(input.aggregateStats.protein)g protein. \(themes)".trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func averages(from dailyStats: [DailyStatInput]) -> (calories: Int, protein: Int) {
        guard !dailyStats.isEmpty else {
            return (0, 0)
        }

        let totals = dailyStats.reduce(into: (calories: 0, protein: 0)) { partialResult, snapshot in
            partialResult.calories += snapshot.calories
            partialResult.protein += snapshot.protein
        }
        return (
            Int((Double(totals.calories) / Double(dailyStats.count)).rounded()),
            Int((Double(totals.protein) / Double(dailyStats.count)).rounded())
        )
    }

    private static func decode<T: Decodable>(_ type: T.Type, from text: String) throws -> T {
        let data = Data(text.utf8)
        return try JSONDecoder().decode(type, from: data)
    }
}

private struct ActiveStateInput: Decodable {
    let windowStart: String
    let windowEnd: String
    let todayMarkdown: String
    let dailyStats: [DailyStatInput]
    let latestMetrics: [MetricInput]
    let trainingStreakDays: Int
    let loggingStreakDays: Int
    let workingWeights: [WorkingWeightInput]
}

private struct DailySummaryInput: Decodable {
    let date: String
    let keyStats: SummaryKeyStats
    let todayMarkdown: String
    let messages: [ConversationInput]
}

private struct PatternsInput: Decodable {
    let summaries: [SummaryInput]
    let currentPatterns: [CurrentPatternInput]
}

private struct IdentityInput: Decodable {
    let currentIdentityMarkdown: String
    let summaries: [SummaryInput]
}

private struct ArchiveRollupInput: Decodable {
    let scope: String
    let startDate: String
    let endDate: String
    let aggregateStats: SummaryKeyStats
    let entries: [ArchiveEntryInput]
}

private struct DailyStatInput: Decodable {
    let date: String
    let calories: Int
    let protein: Int
    let trained: Bool
    let hrv: String?
    let sleep: String?
    let loggedAnything: Bool
}

private struct MetricInput: Decodable {
    let type: String
    let value: String
    let context: String?
    let observedAt: String
}

private struct WorkingWeightInput: Decodable {
    let exercise: String
    let loadText: String
    let observedAt: String
    let summary: String
}

private struct ConversationInput: Decodable {
    let role: String
    let content: String
}

private struct SummaryInput: Decodable {
    let date: String
    let summaryText: String
    let keyStats: SummaryKeyStats
}

private struct CurrentPatternInput: Decodable {
    let key: String
    let description: String
    let evidenceNote: String
    let confidence: String
    let firstObserved: String
    let lastReinforced: String
}

private struct ArchiveEntryInput: Decodable {
    let date: String
    let summaryText: String
    let keyStats: SummaryKeyStats
}

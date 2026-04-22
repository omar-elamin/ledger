import Foundation
import OSLog
import SwiftData

actor MemoryMaintainer {
    static let activeStateSystemPrompt = """
    You maintain Ledger's Level 2 active state snapshot.

    Your job:
    - Convert the provided deterministic structured facts into concise markdown.
    - Use only the numbers and facts in the input. Do not invent targets, trends, or explanations.
    - Keep it factual and current. This is not motivational copy.
    - Call out what is true right now: recent intake averages, recent training cadence, latest recovery/body metrics, and current working weights when present.

    Output rules:
    - Return markdown only.
    - Keep it compact: 4 short sections max.
    - Preserve exact numeric values from the input.
    - If data is missing, say it is missing instead of inferring.
    """

    static let dailySummarySystemPrompt = """
    You maintain Ledger's Level 3 recent narrative.

    Your job:
    - Summarize one day only.
    - Use the supplied conversation snippets and structured logs to write one paragraph of about 40 words.
    - Capture the day's concrete facts and overall tone without adding interpretation that is not supported.

    Output rules:
    - Return a single plain paragraph.
    - No bullets, headings, or prefatory text.
    - No invented facts.
    - Keep named foods, training, and recovery facts specific when they are present.
    """

    static let patternsSystemPrompt = """
    You maintain Ledger's Level 1.5 pattern memory.

    Your job:
    - Review the last 28 daily summaries plus the current stored patterns.
    - Return only durable patterns that are supported by multiple data points.
    - Be conservative. Single events, vibes, and weak hunches do not qualify.
    - New patterns must start at low confidence. Only promote to medium or high when repeated evidence is obvious.
    - Remove patterns that are contradicted or no longer supported by the recent window.

    Output rules:
    - Return JSON only.
    - Use this exact shape:
      {
        "operations": [
          {
            "action": "add" | "update" | "remove",
            "key": "short_snake_case_key",
            "description": "plain-language pattern statement",
            "evidenceNote": "brief concrete evidence",
            "confidence": "low" | "medium" | "high",
            "firstObserved": "YYYY-MM-DD",
            "lastReinforced": "YYYY-MM-DD"
          }
        ]
      }
    - For remove operations, include only action, key, and evidenceNote.
    """

    static let identityUpdateSystemPrompt = """
    You maintain Ledger's Level 1 identity memory.

    Your job:
    - Review the current identity profile, recent daily summaries, and stored patterns.
    - Propose only factual identity updates that are justified by the evidence.
    - Prefer concrete facts such as goals, injuries, hard constraints, stable schedule facts, and explicit stated preferences.
    - Do not rewrite for style. Do not broaden facts into interpretation.

    Output rules:
    - Return JSON only.
    - Use this exact shape:
      {
        "proposals": [
          {
            "kind": "factual" | "interpretive",
            "confidence": "low" | "medium" | "high",
            "key": "short_snake_case_key",
            "value": "fact to store",
            "rationale": "brief evidence-based reason"
          }
        ]
      }
    - Only mark a proposal as factual when it could reasonably be stored as a durable user fact.
    """

    static let archiveRollupSystemPrompt = """
    You compress older Ledger memory into archive summaries.

    Your job:
    - Turn the supplied daily or weekly entries into one paragraph for archive recall.
    - Preserve the main themes, concrete events, and overall direction of the period.
    - Stay grounded in the provided entries and aggregate stats.

    Output rules:
    - Return a single paragraph only.
    - No headings, bullets, or preamble.
    - No invented facts.
    """

    private let modelContainer: ModelContainer
    private let textGenerator: any MemoryTextGeneratingClient
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    private let logger = Logger(subsystem: "com.omarelamin.ledger", category: "MemoryMaintainer")

    init(
        modelContainer: ModelContainer,
        textGenerator: any MemoryTextGeneratingClient,
        calendar: Calendar = .autoupdatingCurrent,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.modelContainer = modelContainer
        self.textGenerator = textGenerator
        self.calendar = calendar
        self.now = now
    }

    func updateActiveState() async throws {
        let context = ModelContext(modelContainer)
        let builder = ContextBuilder(modelContext: context, calendar: calendar, now: now)
        let today = now()
        let todayBounds = builder.dayBounds(for: today)
        let windowStart = calendar.date(byAdding: .day, value: -7, to: todayBounds.start) ?? todayBounds.start
        let windowEnd = todayBounds.end

        let windowData = try builder.structuredData(start: windowStart, end: windowEnd)
        let dailyStats = try dailyStats(from: builder, start: windowStart, through: todayBounds.start)
        let todayMarkdown = builder.todayMarkdown()
        let input = ActiveStatePromptInput(
            windowStart: Self.dayString(windowStart),
            windowEnd: Self.dayString(todayBounds.start),
            todayMarkdown: todayMarkdown,
            dailyStats: dailyStats,
            latestMetrics: latestMetricSnapshots(from: windowData.metrics),
            trainingStreakDays: streakLength(in: dailyStats, keyPath: \.trained),
            loggingStreakDays: loggingStreakLength(in: dailyStats),
            workingWeights: latestWorkingWeights(from: windowData.workoutSets)
        )

        let markdown = try await textGenerator.generateText(
            systemPrompt: Self.activeStateSystemPrompt,
            userPrompt: try encodePrompt(input),
            maxTokens: 700
        )

        try upsertActiveStateSnapshot(
            markdown: markdown,
            generatedAt: today,
            in: context
        )
    }

    func summarizeToday() async throws {
        let context = ModelContext(modelContainer)
        let builder = ContextBuilder(modelContext: context, calendar: calendar, now: now)
        let today = now()
        let bounds = builder.dayBounds(for: today)
        let structured = try builder.structuredData(start: bounds.start, end: bounds.end)
        let messages = try builder.dateRangeMessages(start: bounds.start, end: bounds.end)

        let input = DailySummaryPromptInput(
            date: Self.dayString(bounds.start),
            keyStats: structured.keyStats,
            todayMarkdown: builder.todayMarkdown(),
            messages: messages.map {
                ConversationSnippet(
                    role: $0.role,
                    content: $0.content
                )
            }
        )

        let summaryText = try await textGenerator.generateText(
            systemPrompt: Self.dailySummarySystemPrompt,
            userPrompt: try encodePrompt(input),
            maxTokens: 180
        )

        try upsertDailySummary(
            date: bounds.start,
            summaryText: summaryText,
            keyStats: structured.keyStats,
            in: context
        )
    }

    func updatePatterns() async throws {
        let context = ModelContext(modelContainer)
        let builder = ContextBuilder(modelContext: context, calendar: calendar, now: now)
        let summaries = try builder.recentDailySummaries(limit: 28)
        guard !summaries.isEmpty else {
            return
        }

        let patterns = try fetchPatterns(in: context)
        let input = PatternPromptInput(
            summaries: summaries.map {
                SummarySnapshot(
                    date: Self.dayString($0.date),
                    summaryText: $0.summaryText,
                    keyStats: $0.keyStats
                )
            },
            currentPatterns: patterns.map {
                PatternSnapshot(
                    key: $0.key,
                    description: $0.descriptionText,
                    evidenceNote: $0.evidenceNote,
                    confidence: $0.confidence,
                    firstObserved: Self.dayString($0.firstObserved),
                    lastReinforced: Self.dayString($0.lastReinforced)
                )
            }
        )

        let responseText = try await textGenerator.generateText(
            systemPrompt: Self.patternsSystemPrompt,
            userPrompt: try encodePrompt(input),
            maxTokens: 700
        )
        let response = try decodeJSON(PatternMaintenanceResponse.self, from: responseText)
        try applyPatternOperations(response.operations, in: context)
    }

    func proposeIdentityUpdates() async throws {
        let context = ModelContext(modelContainer)
        let builder = ContextBuilder(modelContext: context, calendar: calendar, now: now)
        let summaries = try builder.recentDailySummaries(limit: 28)
        guard !summaries.isEmpty else {
            return
        }

        let currentProfile = try fetchIdentityProfile(in: context)
        let patterns = try fetchPatterns(in: context)
        let input = IdentityPromptInput(
            currentIdentityMarkdown: currentProfile?.markdownContent ?? "",
            summaries: summaries.map {
                SummarySnapshot(
                    date: Self.dayString($0.date),
                    summaryText: $0.summaryText,
                    keyStats: $0.keyStats
                )
            },
            currentPatterns: patterns.map {
                PatternSnapshot(
                    key: $0.key,
                    description: $0.descriptionText,
                    evidenceNote: $0.evidenceNote,
                    confidence: $0.confidence,
                    firstObserved: Self.dayString($0.firstObserved),
                    lastReinforced: Self.dayString($0.lastReinforced)
                )
            }
        )

        let responseText = try await textGenerator.generateText(
            systemPrompt: Self.identityUpdateSystemPrompt,
            userPrompt: try encodePrompt(input),
            maxTokens: 500
        )
        let response = try decodeJSON(IdentityProposalResponse.self, from: responseText)
        try applyIdentityProposals(response.proposals, in: context)
    }

    func rollupWeek() async throws {
        let context = ModelContext(modelContainer)
        let cutoff = calendar.date(byAdding: .day, value: -28, to: calendar.startOfDay(for: now())) ?? now()
        let summaries = try context.fetch(
            FetchDescriptor<DailySummary>(
                sortBy: [SortDescriptor(\.date, order: .forward)]
            )
        )

        let grouped = Dictionary(grouping: summaries) { summary in
            startOfWeek(for: summary.date)
        }

        for startDate in grouped.keys.sorted() {
            guard
                let interval = calendar.dateInterval(of: .weekOfYear, for: startDate),
                interval.end <= cutoff,
                let items = grouped[startDate]
            else {
                continue
            }

            let endDate = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? startDate
            let summaryText = try await archiveRollupText(
                scope: "week",
                startDate: startDate,
                endDate: endDate,
                entries: items.map {
                    RollupEntrySnapshot(
                        date: Self.dayString($0.date),
                        summaryText: $0.summaryText,
                        keyStats: $0.keyStats
                    )
                }
            )

            try upsertWeeklySummary(
                startDate: startDate,
                endDate: endDate,
                summaryText: summaryText,
                keyStats: aggregate(items.map(\.keyStats)),
                sourceEntries: items,
                in: context
            )
        }
    }

    func rollupMonth() async throws {
        let context = ModelContext(modelContainer)
        let startOfCurrentMonth = calendar.dateInterval(of: .month, for: now())?.start ?? calendar.startOfDay(for: now())
        let summaries = try context.fetch(
            FetchDescriptor<WeeklySummary>(
                sortBy: [SortDescriptor(\.startDate, order: .forward)]
            )
        )

        let eligible = summaries.filter { $0.endDate < startOfCurrentMonth }
        let grouped = Dictionary(grouping: eligible) { summary in
            startOfMonth(for: summary.startDate)
        }

        for startDate in grouped.keys.sorted() {
            guard
                let interval = calendar.dateInterval(of: .month, for: startDate),
                interval.end <= startOfCurrentMonth,
                let items = grouped[startDate]
            else {
                continue
            }

            let endDate = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? startDate
            let summaryText = try await archiveRollupText(
                scope: "month",
                startDate: startDate,
                endDate: endDate,
                entries: items.map {
                    RollupEntrySnapshot(
                        date: "\(Self.dayString($0.startDate)) → \(Self.dayString($0.endDate))",
                        summaryText: $0.summaryText,
                        keyStats: $0.keyStats
                    )
                }
            )

            try upsertMonthlySummary(
                startDate: startDate,
                endDate: endDate,
                summaryText: summaryText,
                keyStats: aggregate(items.map(\.keyStats)),
                sourceEntries: items,
                in: context
            )
        }
    }

    func preGenerateMorningStandup() async {
        logger.debug("Morning standup generation is still a stub.")
    }

    private func archiveRollupText(
        scope: String,
        startDate: Date,
        endDate: Date,
        entries: [RollupEntrySnapshot]
    ) async throws -> String {
        let input = RollupPromptInput(
            scope: scope,
            startDate: Self.dayString(startDate),
            endDate: Self.dayString(endDate),
            aggregateStats: aggregate(entries.map(\.keyStats)),
            entries: entries
        )

        return try await textGenerator.generateText(
            systemPrompt: Self.archiveRollupSystemPrompt,
            userPrompt: try encodePrompt(input),
            maxTokens: 260
        )
    }

    private func dailyStats(
        from builder: ContextBuilder,
        start: Date,
        through todayStart: Date
    ) throws -> [DailyStatSnapshot] {
        let dayCount = calendar.dateComponents([.day], from: start, to: todayStart).day ?? 0
        return try (0 ... max(dayCount, 0)).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else {
                return nil
            }
            let bounds = builder.dayBounds(for: day)
            let structured = try builder.structuredData(start: bounds.start, end: bounds.end)
            return DailyStatSnapshot(
                date: Self.dayString(bounds.start),
                calories: structured.keyStats.calories,
                protein: structured.keyStats.protein,
                trained: structured.keyStats.trained,
                hrv: structured.keyStats.hrv,
                sleep: structured.keyStats.sleep,
                loggedAnything: !structured.meals.isEmpty || !structured.workoutSets.isEmpty || !structured.metrics.isEmpty
            )
        }
    }

    private func latestMetricSnapshots(from metrics: [StoredMetric]) -> [MetricSnapshot] {
        let grouped = Dictionary(grouping: metrics) { $0.type.lowercased() }
        return grouped.keys.sorted().compactMap { key in
            guard let latest = grouped[key]?.max(by: { $0.date < $1.date }) else {
                return nil
            }
            return MetricSnapshot(
                type: latest.type,
                value: latest.value,
                context: latest.context,
                observedAt: Self.timestampString(latest.date)
            )
        }
    }

    private func latestWorkingWeights(from sets: [StoredWorkoutSet]) -> [WorkingWeightSnapshot] {
        let sortedSets = sets.sorted { $0.date > $1.date }
        var latestByExercise: [String: WorkingWeightSnapshot] = [:]

        for set in sortedSets {
            guard latestByExercise[set.exercise] == nil else {
                continue
            }

            guard let loadText = Self.parseLoadText(from: set.summary) else {
                continue
            }

            latestByExercise[set.exercise] = WorkingWeightSnapshot(
                exercise: set.exercise,
                loadText: loadText,
                observedAt: Self.timestampString(set.date),
                summary: set.summary
            )
        }

        return latestByExercise.values.sorted { $0.exercise < $1.exercise }
    }

    private func streakLength(
        in dailyStats: [DailyStatSnapshot],
        keyPath: KeyPath<DailyStatSnapshot, Bool>
    ) -> Int {
        var streak = 0
        for day in dailyStats.reversed() {
            guard day[keyPath: keyPath] else {
                break
            }
            streak += 1
        }
        return streak
    }

    private func loggingStreakLength(in dailyStats: [DailyStatSnapshot]) -> Int {
        var streak = 0
        for day in dailyStats.reversed() {
            guard day.loggedAnything else {
                break
            }
            streak += 1
        }
        return streak
    }

    private func applyPatternOperations(
        _ operations: [PatternOperation],
        in context: ModelContext
    ) throws {
        guard !operations.isEmpty else {
            return
        }

        let existingPatterns = try fetchPatterns(in: context)
        var patternsByKey = Dictionary(uniqueKeysWithValues: existingPatterns.map { ($0.key, $0) })

        for operation in operations {
            switch operation.action {
            case .remove:
                if let existing = patternsByKey.removeValue(forKey: operation.key) {
                    context.delete(existing)
                }
            case .add, .update:
                let firstObserved = operation.firstObserved ?? now()
                let lastReinforced = operation.lastReinforced ?? now()

                if let existing = patternsByKey[operation.key] {
                    existing.descriptionText = operation.description ?? existing.descriptionText
                    existing.evidenceNote = operation.evidenceNote
                    existing.confidence = operation.confidence ?? existing.confidence
                    existing.firstObserved = firstObserved
                    existing.lastReinforced = lastReinforced
                } else {
                    let pattern = Pattern(
                        key: operation.key,
                        descriptionText: operation.description ?? operation.key,
                        evidenceNote: operation.evidenceNote,
                        confidence: operation.confidence ?? .low,
                        firstObserved: firstObserved,
                        lastReinforced: lastReinforced
                    )
                    patternsByKey[operation.key] = pattern
                    context.insert(pattern)
                }
            }
        }

        try context.save()
    }

    private func applyIdentityProposals(
        _ proposals: [IdentityProposal],
        in context: ModelContext
    ) throws {
        guard !proposals.isEmpty else {
            return
        }

        let now = now()
        let profile = try fetchIdentityProfile(in: context)
        var markdown = profile?.markdownContent ?? ""
        var didApply = false

        for proposal in proposals {
            guard !proposal.key.isEmpty, !proposal.value.isEmpty else {
                continue
            }

            if proposal.kind == .factual, proposal.confidence == .high {
                markdown = IdentityProfileDocument.upserting(
                    key: proposal.key,
                    value: proposal.value,
                    into: markdown
                )
                didApply = true
            } else {
                logger.info(
                    "Queued identity proposal kind=\(proposal.kind.rawValue, privacy: .public) confidence=\(proposal.confidence.rawValue, privacy: .public) key=\(proposal.key, privacy: .public) rationale=\(proposal.rationale, privacy: .public)"
                )
            }
        }

        guard didApply else {
            return
        }

        if let profile {
            profile.markdownContent = markdown
            profile.lastUpdated = now
        } else {
            context.insert(
                IdentityProfile(
                    scope: IdentityProfile.defaultScope,
                    markdownContent: markdown,
                    lastUpdated: now
                )
            )
        }

        try context.save()
    }

    private func upsertActiveStateSnapshot(
        markdown: String,
        generatedAt: Date,
        in context: ModelContext
    ) throws {
        if let existing = try fetchActiveStateSnapshot(in: context) {
            existing.markdownContent = markdown
            existing.generatedAt = generatedAt
        } else {
            context.insert(
                ActiveStateSnapshot(
                    scope: ActiveStateSnapshot.defaultScope,
                    markdownContent: markdown,
                    generatedAt: generatedAt
                )
            )
        }

        try context.save()
    }

    private func upsertDailySummary(
        date: Date,
        summaryText: String,
        keyStats: SummaryKeyStats,
        in context: ModelContext
    ) throws {
        var descriptor = FetchDescriptor<DailySummary>(
            predicate: #Predicate { summary in
                summary.date == date
            }
        )
        descriptor.fetchLimit = 1

        if let existing = try context.fetch(descriptor).first {
            existing.summaryText = summaryText
            existing.keyStats = keyStats
            existing.createdAt = now()
        } else {
            context.insert(
                DailySummary(
                    date: date,
                    summaryText: summaryText,
                    keyStats: keyStats,
                    createdAt: now()
                )
            )
        }

        try context.save()
    }

    private func upsertWeeklySummary(
        startDate: Date,
        endDate: Date,
        summaryText: String,
        keyStats: SummaryKeyStats,
        sourceEntries: [DailySummary],
        in context: ModelContext
    ) throws {
        var descriptor = FetchDescriptor<WeeklySummary>(
            predicate: #Predicate { summary in
                summary.startDate == startDate
            }
        )
        descriptor.fetchLimit = 1

        if let existing = try context.fetch(descriptor).first {
            existing.endDate = endDate
            existing.summaryText = summaryText
            existing.keyStats = keyStats
            existing.createdAt = now()
        } else {
            context.insert(
                WeeklySummary(
                    startDate: startDate,
                    endDate: endDate,
                    summaryText: summaryText,
                    keyStats: keyStats,
                    createdAt: now()
                )
            )
        }

        for entry in sourceEntries {
            context.delete(entry)
        }

        try context.save()
    }

    private func upsertMonthlySummary(
        startDate: Date,
        endDate: Date,
        summaryText: String,
        keyStats: SummaryKeyStats,
        sourceEntries: [WeeklySummary],
        in context: ModelContext
    ) throws {
        var descriptor = FetchDescriptor<MonthlySummary>(
            predicate: #Predicate { summary in
                summary.startDate == startDate
            }
        )
        descriptor.fetchLimit = 1

        if let existing = try context.fetch(descriptor).first {
            existing.endDate = endDate
            existing.summaryText = summaryText
            existing.keyStats = keyStats
            existing.createdAt = now()
        } else {
            context.insert(
                MonthlySummary(
                    startDate: startDate,
                    endDate: endDate,
                    summaryText: summaryText,
                    keyStats: keyStats,
                    createdAt: now()
                )
            )
        }

        for entry in sourceEntries {
            context.delete(entry)
        }

        try context.save()
    }

    private func fetchIdentityProfile(in context: ModelContext) throws -> IdentityProfile? {
        var descriptor = FetchDescriptor<IdentityProfile>(
            predicate: #Predicate { profile in
                profile.scope == "default"
            }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func fetchActiveStateSnapshot(in context: ModelContext) throws -> ActiveStateSnapshot? {
        var descriptor = FetchDescriptor<ActiveStateSnapshot>(
            predicate: #Predicate { snapshot in
                snapshot.scope == "default"
            }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func fetchPatterns(in context: ModelContext) throws -> [Pattern] {
        try context.fetch(
            FetchDescriptor<Pattern>(
                sortBy: [SortDescriptor(\.lastReinforced, order: .reverse)]
            )
        )
    }

    private func aggregate(_ stats: [SummaryKeyStats]) -> SummaryKeyStats {
        guard !stats.isEmpty else {
            return .empty
        }

        let totalCalories = stats.reduce(0) { $0 + $1.calories }
        let totalProtein = stats.reduce(0) { $0 + $1.protein }
        let count = stats.count

        return SummaryKeyStats(
            calories: Int((Double(totalCalories) / Double(count)).rounded()),
            protein: Int((Double(totalProtein) / Double(count)).rounded()),
            trained: stats.contains(where: \.trained),
            hrv: stats.reversed().compactMap(\.hrv).first,
            sleep: stats.reversed().compactMap(\.sleep).first
        )
    }

    private func encodePrompt<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        guard let string = String(data: data, encoding: .utf8) else {
            throw ClaudeClientError.invalidResponse
        }
        return string
    }

    private func decodeJSON<T: Decodable>(
        _ type: T.Type,
        from responseText: String
    ) throws -> T {
        let cleaned = normalizedJSONText(from: responseText)
        guard let data = cleaned.data(using: .utf8) else {
            throw ClaudeClientError.invalidResponse
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let rawValue = try container.decode(String.self)
            if let date = Self.iso8601.date(from: rawValue) ?? Self.dayFormatter.date(from: rawValue) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported date: \(rawValue)"
            )
        }

        return try decoder.decode(type, from: data)
    }

    private func normalizedJSONText(from responseText: String) -> String {
        let trimmed = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
        let body: String

        if trimmed.hasPrefix("```") {
            let lines = trimmed.components(separatedBy: .newlines)
            body = lines
                .dropFirst()
                .dropLast()
                .joined(separator: "\n")
        } else {
            body = trimmed
        }

        guard
            let startIndex = body.firstIndex(where: { $0 == "{" || $0 == "[" }),
            let endIndex = body.lastIndex(where: { $0 == "}" || $0 == "]" })
        else {
            return body
        }

        return String(body[startIndex ... endIndex])
    }

    private func startOfWeek(for date: Date) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    private func startOfMonth(for date: Date) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    private static func parseLoadText(from summary: String) -> String? {
        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let lowercased = trimmed.lowercased()
        if lowercased.contains("bw") {
            return "bw"
        }

        let patterns = [
            #"@\s*(\d+(?:\.\d+)?)\s*kg"#,
            #"(\d+(?:\.\d+)?)\s*kg\s*[×x]"#
        ]

        for pattern in patterns {
            guard
                let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                let match = regex.firstMatch(
                    in: trimmed,
                    range: NSRange(location: 0, length: trimmed.utf16.count)
                ),
                match.numberOfRanges > 1,
                let range = Range(match.range(at: 1), in: trimmed)
            else {
                continue
            }
            return "\(trimmed[range])kg"
        }

        return nil
    }

    private static func dayString(_ date: Date) -> String {
        dayFormatter.string(from: date)
    }

    private static func timestampString(_ date: Date) -> String {
        timestampFormatter.string(from: date)
    }

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = .autoupdatingCurrent
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = .autoupdatingCurrent
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()
}

private struct ActiveStatePromptInput: Encodable {
    let windowStart: String
    let windowEnd: String
    let todayMarkdown: String
    let dailyStats: [DailyStatSnapshot]
    let latestMetrics: [MetricSnapshot]
    let trainingStreakDays: Int
    let loggingStreakDays: Int
    let workingWeights: [WorkingWeightSnapshot]
}

private struct DailySummaryPromptInput: Encodable {
    let date: String
    let keyStats: SummaryKeyStats
    let todayMarkdown: String
    let messages: [ConversationSnippet]
}

private struct PatternPromptInput: Encodable {
    let summaries: [SummarySnapshot]
    let currentPatterns: [PatternSnapshot]
}

private struct IdentityPromptInput: Encodable {
    let currentIdentityMarkdown: String
    let summaries: [SummarySnapshot]
    let currentPatterns: [PatternSnapshot]
}

private struct RollupPromptInput: Encodable {
    let scope: String
    let startDate: String
    let endDate: String
    let aggregateStats: SummaryKeyStats
    let entries: [RollupEntrySnapshot]
}

private struct DailyStatSnapshot: Encodable {
    let date: String
    let calories: Int
    let protein: Int
    let trained: Bool
    let hrv: String?
    let sleep: String?
    let loggedAnything: Bool
}

private struct MetricSnapshot: Encodable {
    let type: String
    let value: String
    let context: String?
    let observedAt: String
}

private struct WorkingWeightSnapshot: Encodable, Equatable {
    let exercise: String
    let loadText: String
    let observedAt: String
    let summary: String
}

private struct ConversationSnippet: Encodable {
    let role: String
    let content: String
}

private struct SummarySnapshot: Encodable {
    let date: String
    let summaryText: String
    let keyStats: SummaryKeyStats
}

private struct PatternSnapshot: Encodable {
    let key: String
    let description: String
    let evidenceNote: String
    let confidence: PatternConfidence
    let firstObserved: String
    let lastReinforced: String
}

private struct RollupEntrySnapshot: Encodable {
    let date: String
    let summaryText: String
    let keyStats: SummaryKeyStats
}

private struct PatternMaintenanceResponse: Decodable {
    let operations: [PatternOperation]
}

private struct PatternOperation: Decodable {
    let action: PatternOperationAction
    let key: String
    let description: String?
    let evidenceNote: String
    let confidence: PatternConfidence?
    let firstObserved: Date?
    let lastReinforced: Date?
}

private enum PatternOperationAction: String, Decodable {
    case add
    case update
    case remove
}

private struct IdentityProposalResponse: Decodable {
    let proposals: [IdentityProposal]
}

private struct IdentityProposal: Decodable {
    let kind: IdentityProposalKind
    let confidence: PatternConfidence
    let key: String
    let value: String
    let rationale: String
}

private enum IdentityProposalKind: String, Decodable {
    case factual
    case interpretive
}

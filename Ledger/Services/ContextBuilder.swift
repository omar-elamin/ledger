import Foundation
import SwiftData

struct ContextBuilder {
    let modelContext: ModelContext
    let calendar: Calendar
    let now: @Sendable () -> Date

    init(
        modelContext: ModelContext,
        calendar: Calendar = .autoupdatingCurrent,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.modelContext = modelContext
        self.calendar = calendar
        self.now = now
    }

    func buildChatContext() -> String {
        let todayLabel = shortDateFormatter.string(from: now())
        let sections = [
            "## Who this person is\n\(identityContent())",
            "## Patterns observed\n\(patternsContent())",
            "## Where they are right now\n\(activeStateContent())",
            "## Recent days\n\(recentDaysContent())",
            "## Today so far (\(todayLabel))\n\(todayMarkdown())"
        ]
        return sections.joined(separator: "\n\n")
    }

    func todayMarkdown() -> String {
        let bounds = dayBounds(for: now())

        do {
            let meals = try fetchMeals(start: bounds.start, end: bounds.end)
            let workouts = try fetchWorkoutSets(start: bounds.start, end: bounds.end)
            let metrics = try fetchMetrics(start: bounds.start, end: bounds.end)

            guard !meals.isEmpty || !workouts.isEmpty || !metrics.isEmpty else {
                return "Nothing logged yet today."
            }

            var lines: [String] = []

            if !meals.isEmpty {
                let calories = meals.reduce(0) { $0 + $1.calories }
                let protein = meals.reduce(0) { $0 + $1.protein }
                lines.append("Meals total: \(calories) cal, \(protein)g protein")
                lines.append(contentsOf: meals.map { "- " + LogTextFormatter.mealLine($0) })
            }

            if !workouts.isEmpty {
                if !lines.isEmpty {
                    lines.append("")
                }
                lines.append("Training")
                lines.append(contentsOf: workouts.map { "- " + LogTextFormatter.workoutLine($0) })
            }

            if !metrics.isEmpty {
                if !lines.isEmpty {
                    lines.append("")
                }
                lines.append("Body / recovery")
                lines.append(contentsOf: metrics.map { "- " + LogTextFormatter.metricLine($0) })
            }

            return lines.joined(separator: "\n")
        } catch {
            print("Failed to build today's markdown context: \(error)")
            return "Nothing logged yet today."
        }
    }

    func todayStructuredData() throws -> StructuredDayData {
        let bounds = dayBounds(for: now())
        return try structuredData(start: bounds.start, end: bounds.end)
    }

    func structuredData(start: Date, end: Date) throws -> StructuredDayData {
        StructuredDayData(
            meals: try fetchMeals(start: start, end: end),
            workoutSets: try fetchWorkoutSets(start: start, end: end),
            metrics: try fetchMetrics(start: start, end: end)
        )
    }

    func dateRangeMessages(start: Date, end: Date) throws -> [StoredMessage] {
        try modelContext.fetch(
            FetchDescriptor<StoredMessage>(
                predicate: #Predicate {
                    $0.timestamp >= start && $0.timestamp < end
                },
                sortBy: [SortDescriptor(\.timestamp, order: .forward)]
            )
        )
    }

    func recentDailySummaries(limit: Int) throws -> [DailySummary] {
        var descriptor = FetchDescriptor<DailySummary>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try modelContext.fetch(descriptor).sorted { $0.date < $1.date }
    }

    func mediumOrHighPatterns() throws -> [Pattern] {
        try modelContext.fetch(
            FetchDescriptor<Pattern>(
                sortBy: [
                    SortDescriptor(\.lastReinforced, order: .reverse),
                    SortDescriptor(\.firstObserved, order: .reverse)
                ]
            )
        )
        .filter { pattern in
            pattern.confidence == .medium || pattern.confidence == .high
        }
    }

    func identityProfile() throws -> IdentityProfile? {
        var descriptor = FetchDescriptor<IdentityProfile>(
            predicate: #Predicate { profile in
                profile.scope == "default"
            }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    func activeStateSnapshot() throws -> ActiveStateSnapshot? {
        var descriptor = FetchDescriptor<ActiveStateSnapshot>(
            predicate: #Predicate { snapshot in
                snapshot.scope == "default"
            }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    func archiveMatches(query: String) throws -> [ArchiveSearchMatch] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return []
        }

        let lowercasedQuery = trimmedQuery.lowercased()
        let weekly = try modelContext.fetch(
            FetchDescriptor<WeeklySummary>(
                sortBy: [SortDescriptor(\.startDate, order: .reverse)]
            )
        )
        let monthly = try modelContext.fetch(
            FetchDescriptor<MonthlySummary>(
                sortBy: [SortDescriptor(\.startDate, order: .reverse)]
            )
        )

        let weekMatches = weekly.compactMap { summary -> ArchiveSearchMatch? in
            guard summary.summaryText.lowercased().contains(lowercasedQuery) else {
                return nil
            }
            return ArchiveSearchMatch(
                scope: "week",
                startDate: summary.startDate,
                endDate: summary.endDate,
                summaryText: summary.summaryText
            )
        }

        let monthMatches = monthly.compactMap { summary -> ArchiveSearchMatch? in
            guard summary.summaryText.lowercased().contains(lowercasedQuery) else {
                return nil
            }
            return ArchiveSearchMatch(
                scope: "month",
                startDate: summary.startDate,
                endDate: summary.endDate,
                summaryText: summary.summaryText
            )
        }

        return (weekMatches + monthMatches)
            .sorted { $0.startDate > $1.startDate }
            .prefix(3)
            .map { $0 }
    }

    func archiveSearchMarkdown(query: String) throws -> String {
        let matches = try archiveMatches(query: query)
        guard !matches.isEmpty else {
            return "No archive matches for \"\(query)\"."
        }

        return matches.map { match in
            "- \(match.label): \(match.summaryText)"
        }
        .joined(separator: "\n")
    }

    func startOfDay(for date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    func dayBounds(for date: Date) -> (start: Date, end: Date) {
        let start = startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        return (start, end)
    }

    private func identityContent() -> String {
        do {
            let profile = try identityProfile()
            let content = profile?.markdownContent.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return content.isEmpty ? "No stable identity facts recorded yet." : content
        } catch {
            print("Failed to fetch identity profile: \(error)")
            return "No stable identity facts recorded yet."
        }
    }

    private func patternsContent() -> String {
        do {
            let patterns = try mediumOrHighPatterns()
            guard !patterns.isEmpty else {
                return "- None yet."
            }

            return patterns.map { pattern in
                "- [\(pattern.confidence.rawValue)] \(pattern.descriptionText) Evidence: \(pattern.evidenceNote)"
            }
            .joined(separator: "\n")
        } catch {
            print("Failed to fetch patterns: \(error)")
            return "- None yet."
        }
    }

    private func activeStateContent() -> String {
        do {
            let snapshot = try activeStateSnapshot()
            let content = snapshot?.markdownContent.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return content.isEmpty ? "No active state snapshot yet." : content
        } catch {
            print("Failed to fetch active state snapshot: \(error)")
            return "No active state snapshot yet."
        }
    }

    private func recentDaysContent() -> String {
        do {
            let summaries = try recentDailySummaries(limit: 28)
            guard !summaries.isEmpty else {
                return "No daily summaries yet."
            }

            return summaries.map { summary in
                "\(dateWithOffset(for: summary.date)): \(summary.summaryText)"
            }
            .joined(separator: "\n")
        } catch {
            print("Failed to fetch recent daily summaries: \(error)")
            return "No daily summaries yet."
        }
    }

    private func dateWithOffset(for date: Date) -> String {
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: date),
            to: calendar.startOfDay(for: now())
        ).day ?? 0

        switch days {
        case ...0:
            return "today"
        case 1:
            return "yesterday"
        case 2...7:
            return "\(days) days ago"
        default:
            return "\(shortDateFormatter.string(from: date)) (\(days) days ago)"
        }
    }

    private var shortDateFormatter: DateFormatter {
        // Locale pinned to en_US_POSIX so the LLM context always reads "Apr 23"
        // regardless of the device/test locale. TZ follows the injected calendar
        // so tests with a UTC calendar and production with device-local calendar
        // both render consistent day labels.
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "MMM d"
        return formatter
    }

    private func fetchMeals(start: Date, end: Date) throws -> [StoredMeal] {
        try modelContext.fetch(
            FetchDescriptor<StoredMeal>(
                predicate: #Predicate {
                    $0.date >= start && $0.date < end
                },
                sortBy: [SortDescriptor(\.date, order: .forward)]
            )
        )
    }

    private func fetchWorkoutSets(start: Date, end: Date) throws -> [StoredWorkoutSet] {
        try modelContext.fetch(
            FetchDescriptor<StoredWorkoutSet>(
                predicate: #Predicate {
                    $0.date >= start && $0.date < end
                },
                sortBy: [SortDescriptor(\.date, order: .forward)]
            )
        )
    }

    private func fetchMetrics(start: Date, end: Date) throws -> [StoredMetric] {
        try modelContext.fetch(
            FetchDescriptor<StoredMetric>(
                predicate: #Predicate {
                    $0.date >= start && $0.date < end
                },
                sortBy: [SortDescriptor(\.date, order: .forward)]
            )
        )
    }

    private static let summaryDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = .autoupdatingCurrent
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "EEE MMM d"
        return formatter
    }()

}

struct StructuredDayData {
    let meals: [StoredMeal]
    let workoutSets: [StoredWorkoutSet]
    let metrics: [StoredMetric]

    var keyStats: SummaryKeyStats {
        SummaryKeyStats(
            calories: meals.reduce(0) { $0 + $1.calories },
            protein: meals.reduce(0) { $0 + $1.protein },
            trained: !workoutSets.isEmpty,
            hrv: metrics.last(where: { $0.type.lowercased() == "hrv" })?.value,
            sleep: metrics.last(where: { $0.type.lowercased() == "sleep" })?.value
        )
    }
}

struct ArchiveSearchMatch: Identifiable, Equatable {
    let scope: String
    let startDate: Date
    let endDate: Date
    let summaryText: String

    var id: String { "\(scope)-\(startDate.timeIntervalSince1970)" }

    var label: String {
        let formatter = DateIntervalFormatter()
        formatter.calendar = .autoupdatingCurrent
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateTemplate = "MMM d"
        let period = formatter.string(from: startDate, to: endDate)
        return scope == "month" ? "Month \(period)" : "Week \(period)"
    }
}

import Foundation

struct HistoryDaySnapshot: Identifiable {
    let date: Date
    let dayLabel: String
    let calories: Int
    let protein: Int
    let summary: String

    var id: Date { date }
}

struct HistoryWeekSection: Identifiable {
    let startDate: Date
    let label: String
    let narrative: String?
    let days: [HistoryDaySnapshot]

    var id: Date { startDate }
}

enum LogTextFormatter {
    static func mealLine(_ meal: StoredMeal) -> String {
        "\(meal.descriptionText) (~\(meal.calories) cal, \(meal.protein)g protein)"
    }

    static func workoutLine(_ workout: StoredWorkoutSet, includeNotes: Bool = true) -> String {
        if includeNotes, let notes = workout.notes, !notes.isEmpty {
            return "\(workout.exercise)  \(workout.summary)  \(notes)"
        }
        return "\(workout.exercise)  \(workout.summary)"
    }

    static func metricLine(_ metric: StoredMetric) -> String {
        let type = metricTypeLabel(metric.type)
        if let context = metric.context, !context.isEmpty {
            return "\(type) \(metric.value) \(context)"
        }
        return "\(type) \(metric.value)"
    }

    static func metricSummary(_ metric: StoredMetric) -> String {
        metricLine(metric)
    }

    private static func metricTypeLabel(_ rawType: String) -> String {
        switch rawType.lowercased() {
        case "hrv":
            return "HRV"
        case "sleep":
            return "Sleep"
        case "weight":
            return "Weight"
        case "mood":
            return "Mood"
        default:
            return rawType.capitalized
        }
    }
}

enum HistoryTimelineBuilder {
    static func build(
        meals: [StoredMeal],
        workoutSets: [StoredWorkoutSet],
        metrics: [StoredMetric],
        anchorDate: Date,
        calendar: Calendar = .autoupdatingCurrent,
        narrativeProvider: (Date) -> String? = { _ in nil }
    ) -> [HistoryWeekSection] {
        var dayBuckets: [Date: DayBucket] = [:]

        for meal in meals {
            let dayStart = calendar.startOfDay(for: meal.date)
            dayBuckets[dayStart, default: DayBucket(date: dayStart)].meals.append(meal)
        }

        for workout in workoutSets {
            let dayStart = calendar.startOfDay(for: workout.date)
            dayBuckets[dayStart, default: DayBucket(date: dayStart)].workoutSets.append(workout)
        }

        for metric in metrics {
            let dayStart = calendar.startOfDay(for: metric.date)
            dayBuckets[dayStart, default: DayBucket(date: dayStart)].metrics.append(metric)
        }

        let dayLabelFormatter = DateFormatter()
        dayLabelFormatter.calendar = calendar
        dayLabelFormatter.locale = .autoupdatingCurrent
        dayLabelFormatter.timeZone = .autoupdatingCurrent
        dayLabelFormatter.dateFormat = "EEE"

        let snapshots = dayBuckets.values
            .sorted { $0.date > $1.date }
            .map { bucket in
                HistoryDaySnapshot(
                    date: bucket.date,
                    dayLabel: dayLabelFormatter.string(from: bucket.date),
                    calories: bucket.meals.reduce(0) { $0 + $1.calories },
                    protein: bucket.meals.reduce(0) { $0 + $1.protein },
                    summary: summary(for: bucket)
                )
            }

        let groupedByWeek = Dictionary(grouping: snapshots) { snapshot in
            calendar.dateInterval(of: .weekOfYear, for: snapshot.date)?.start ?? snapshot.date
        }

        let currentWeekStart = calendar.dateInterval(of: .weekOfYear, for: anchorDate)?.start
        let previousWeekStart = currentWeekStart.flatMap {
            calendar.date(byAdding: .weekOfYear, value: -1, to: $0)
        }

        return groupedByWeek.keys
            .sorted(by: >)
            .map { weekStart in
                HistoryWeekSection(
                    startDate: weekStart,
                    label: weekLabel(
                        for: weekStart,
                        currentWeekStart: currentWeekStart,
                        previousWeekStart: previousWeekStart,
                        anchorDate: anchorDate,
                        calendar: calendar
                    ),
                    narrative: narrativeProvider(weekStart),
                    days: groupedByWeek[weekStart, default: []]
                        .sorted { $0.date > $1.date }
                )
            }
    }

    private static func summary(for bucket: DayBucket) -> String {
        let workouts = bucket.workoutSets.sorted { $0.date > $1.date }
        let prioritizedMetrics = bucket.metrics.sorted(by: compareMetrics)

        if let workout = workouts.first {
            var parts = [LogTextFormatter.workoutLine(workout, includeNotes: false)]
            if workouts.count > 1 {
                parts[0] += " +\(workouts.count - 1) more"
            }
            if let notableMetric = prioritizedMetrics.first {
                parts.append(LogTextFormatter.metricSummary(notableMetric))
            }
            return parts.joined(separator: " · ")
        }

        if !prioritizedMetrics.isEmpty {
            return prioritizedMetrics
                .prefix(2)
                .map(LogTextFormatter.metricSummary)
                .joined(separator: " · ")
        }

        let mealCount = bucket.meals.count
        let proteinTotal = bucket.meals.reduce(0) { $0 + $1.protein }
        let mealLabel = mealCount == 1 ? "1 meal" : "\(mealCount) meals"
        return "\(mealLabel), \(proteinTotal)g protein"
    }

    private static func compareMetrics(_ lhs: StoredMetric, _ rhs: StoredMetric) -> Bool {
        let lhsRank = metricPriority(lhs.type)
        let rhsRank = metricPriority(rhs.type)
        if lhsRank == rhsRank {
            return lhs.date > rhs.date
        }
        return lhsRank < rhsRank
    }

    private static func metricPriority(_ type: String) -> Int {
        switch type.lowercased() {
        case "hrv":
            return 0
        case "sleep":
            return 1
        case "weight":
            return 2
        case "mood":
            return 3
        default:
            return 4
        }
    }

    private static func weekLabel(
        for weekStart: Date,
        currentWeekStart: Date?,
        previousWeekStart: Date?,
        anchorDate: Date,
        calendar: Calendar
    ) -> String {
        if let currentWeekStart, weekStart == currentWeekStart {
            return "This week"
        }

        if let previousWeekStart, weekStart == previousWeekStart {
            return "Last week"
        }

        let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        let formatter = DateIntervalFormatter()
        formatter.calendar = calendar
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = .autoupdatingCurrent

        let sameAnchorYear = calendar.isDate(weekStart, equalTo: anchorDate, toGranularity: .year) &&
            calendar.isDate(weekEnd, equalTo: anchorDate, toGranularity: .year)
        formatter.dateTemplate = sameAnchorYear ? "MMM d" : "MMM d, yyyy"
        return formatter.string(from: weekStart, to: weekEnd)
    }
}

private struct DayBucket {
    let date: Date
    var meals: [StoredMeal] = []
    var workoutSets: [StoredWorkoutSet] = []
    var metrics: [StoredMetric] = []
}

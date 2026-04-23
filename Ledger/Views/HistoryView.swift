import SwiftUI
import SwiftData

struct HistoryView: View {
    let dayAnchorController: DayAnchorController

    @Query(sort: [SortDescriptor(\StoredMeal.date, order: .reverse)])
    private var meals: [StoredMeal]
    @Query(sort: [SortDescriptor(\StoredWorkoutSet.date, order: .reverse)])
    private var workoutSets: [StoredWorkoutSet]
    @Query(sort: [SortDescriptor(\StoredMetric.date, order: .reverse)])
    private var metrics: [StoredMetric]

    private var weeks: [HistoryWeekSection] {
        let anchor = dayAnchorController.dayAnchor
        let built = HistoryTimelineBuilder.build(
            meals: meals,
            workoutSets: workoutSets,
            metrics: metrics,
            anchorDate: anchor,
            narrativeProvider: { weekStart in
                MockHistoryNarratives.narrative(
                    forWeekStartingOn: weekStart,
                    anchorDate: anchor
                )
            }
        )

        // Stub narrative for the just-getting-started case: only the current
        // week exists and it's sparse.
        if built.count == 1, built[0].days.count < 3 {
            let only = built[0]
            return [
                HistoryWeekSection(
                    startDate: only.startDate,
                    label: only.label,
                    narrative: MockHistoryNarratives.justGettingStarted,
                    days: only.days
                )
            ]
        }
        return built
    }

    var body: some View {
        ZStack {
            if weeks.isEmpty {
                Text("Your history will appear here as the days accumulate.")
                    .font(Typography.serifBody(17))
                    .foregroundStyle(Color.ledgerTextTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("history.emptyState")
            } else {
                ScrollView {
                    weeksStack
                        .padding(.horizontal, 24)
                        .padding(.top, 24)
                        .padding(.bottom, 60)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .background(Color.ledgerBg)
        .accessibilityIdentifier("history.root")
    }

    private var weeksStack: some View {
        VStack(alignment: .leading, spacing: 40) {
            ForEach(weeks) { week in
                weekBlock(week)
            }
            Spacer(minLength: 0)
        }
    }

    private func weekBlock(_ week: HistoryWeekSection) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(week.label.uppercased())
                .smallCapsLabel(size: 12)
                .accessibilityIdentifier(weekHeaderIdentifier(for: week.startDate))

            if let narrative = week.narrative {
                Text(narrative)
                    .font(Typography.serifBody(18))
                    .foregroundStyle(Color.ledgerTextPrimary)
                    .lineSpacing(6)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier(weekNarrativeIdentifier(for: week.startDate))
            }

            VStack(alignment: .leading, spacing: 14) {
                ForEach(week.days) { day in
                    dayRow(day)
                }
            }
        }
    }

    private func dayRow(_ day: HistoryDaySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(day.dayLabel)
                    .font(Typography.roundedNumber(17, weight: .medium))
                    .foregroundStyle(Color.ledgerTextSecondary)
                    .accessibilityIdentifier(dayDayLabelIdentifier(for: day.date))
                Text("\(LedgerFormat.number(day.calories))c · \(LedgerFormat.number(day.protein))p")
                    .font(Typography.roundedNumber(14))
                    .foregroundStyle(Color.ledgerTextTertiary)
                    .accessibilityIdentifier(dayTotalsIdentifier(for: day.date))
                Spacer(minLength: 0)
            }
            Text(day.summary)
                .font(Typography.serifBody(15))
                .foregroundStyle(Color.ledgerTextTertiary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(daySummaryIdentifier(for: day.date))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(dayRowIdentifier(for: day.date))
    }

    private func dayRowIdentifier(for date: Date) -> String {
        "history.dayRow.\(rowDateKey(for: date))"
    }

    private func dayTotalsIdentifier(for date: Date) -> String {
        "history.dayTotals.\(rowDateKey(for: date))"
    }

    private func daySummaryIdentifier(for date: Date) -> String {
        "history.daySummary.\(rowDateKey(for: date))"
    }

    private func dayDayLabelIdentifier(for date: Date) -> String {
        "history.dayLabel.\(rowDateKey(for: date))"
    }

    private func weekHeaderIdentifier(for date: Date) -> String {
        "history.week.\(rowDateKey(for: date)).header"
    }

    private func weekNarrativeIdentifier(for date: Date) -> String {
        "history.week.\(rowDateKey(for: date)).narrative"
    }

    private func rowDateKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = .autoupdatingCurrent
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

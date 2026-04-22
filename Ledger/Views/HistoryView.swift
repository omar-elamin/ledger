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
        HistoryTimelineBuilder.build(
            meals: meals,
            workoutSets: workoutSets,
            metrics: metrics,
            anchorDate: dayAnchorController.dayAnchor
        )
    }

    var body: some View {
        ZStack {
            if weeks.isEmpty {
                VStack(spacing: 10) {
                    Text("No history yet.")
                        .font(Typography.serifBody(17))
                        .foregroundStyle(Color.ledgerTextSecondary)
                }
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
        VStack(alignment: .leading, spacing: 28) {
            ForEach(Array(weeks.enumerated()), id: \.element.id) { index, week in
                if index > 0 {
                    Rectangle()
                        .fill(Color.ledgerHairline)
                        .frame(height: 1)
                        .padding(.top, 4)
                }

                VStack(alignment: .leading, spacing: 20) {
                    Text(week.label)
                        .smallCapsLabel(size: 12)
                        .padding(.bottom, 2)

                    VStack(alignment: .leading, spacing: 22) {
                        ForEach(week.days) { day in
                            Button(action: {}) {
                                dayRow(day)
                            }
                            .buttonStyle(PressableRowStyle())
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier(dayRowIdentifier(for: day.date))
                        }
                    }
                }
            }

            Spacer(minLength: 40)
        }
    }

    private func dayRow(_ day: HistoryDaySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(day.dayLabel)
                    .font(Typography.roundedNumber(17, weight: .medium))
                    .foregroundStyle(Color.ledgerTextPrimary)
                    .accessibilityIdentifier(dayDayLabelIdentifier(for: day.date))
                Text("\(LedgerFormat.number(day.calories))c · \(LedgerFormat.number(day.protein))p")
                    .font(Typography.roundedNumber(14))
                    .foregroundStyle(Color.ledgerTextTertiary)
                    .accessibilityIdentifier(dayTotalsIdentifier(for: day.date))
                Spacer(minLength: 0)
            }
            Text(day.summary)
                .font(Typography.serifBody(15))
                .foregroundStyle(Color.ledgerTextSecondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(daySummaryIdentifier(for: day.date))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(dayRowIdentifier(for: day.date))
    }

    private func dayRowIdentifier(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = .autoupdatingCurrent
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "yyyy-MM-dd"
        return "history.dayRow.\(formatter.string(from: date))"
    }

    private func dayTotalsIdentifier(for date: Date) -> String {
        dayRowIdentifier(for: date).replacingOccurrences(of: "dayRow", with: "dayTotals")
    }

    private func daySummaryIdentifier(for date: Date) -> String {
        dayRowIdentifier(for: date).replacingOccurrences(of: "dayRow", with: "daySummary")
    }

    private func dayDayLabelIdentifier(for date: Date) -> String {
        dayRowIdentifier(for: date).replacingOccurrences(of: "dayRow", with: "dayLabel")
    }
}

import SwiftUI
import SwiftData

struct TodayLogView: View {
    let dayAnchorController: DayAnchorController

    var body: some View {
        ZStack {
            TodayLogDayView(date: dayAnchorController.dayAnchor)
                .id(dayAnchorController.dayAnchor)
        }
        .background(Color.ledgerBg)
        .accessibilityIdentifier("todayLog.root")
    }
}

private struct TodayLogDayView: View {
    private let date: Date

    @Query private var meals: [StoredMeal]
    @Query private var workoutSets: [StoredWorkoutSet]
    @Query private var metrics: [StoredMetric]

    init(date: Date = .now) {
        self.date = date

        let calendar = Calendar.autoupdatingCurrent
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay

        _meals = Query(
            filter: #Predicate<StoredMeal> {
                $0.date >= startOfDay && $0.date < endOfDay
            },
            sort: [SortDescriptor(\StoredMeal.date, order: .forward)]
        )
        _workoutSets = Query(
            filter: #Predicate<StoredWorkoutSet> {
                $0.date >= startOfDay && $0.date < endOfDay
            },
            sort: [SortDescriptor(\StoredWorkoutSet.date, order: .forward)]
        )
        _metrics = Query(
            filter: #Predicate<StoredMetric> {
                $0.date >= startOfDay && $0.date < endOfDay
            },
            sort: [SortDescriptor(\StoredMetric.date, order: .forward)]
        )
    }

    private var dateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: date)
    }

    private var calorieTotal: Int {
        meals.reduce(0) { $0 + $1.calories }
    }

    private var proteinTotal: Int {
        meals.reduce(0) { $0 + $1.protein }
    }

    private var caloriesString: String {
        "\(LedgerFormat.number(calorieTotal)) cal"
    }

    private var proteinString: String {
        "\(LedgerFormat.number(proteinTotal))g protein"
    }

    private var mealItems: [String] {
        meals.map(LogTextFormatter.mealLine)
    }

    private var workoutItems: [String] {
        workoutSets.map { LogTextFormatter.workoutLine($0) }
    }

    private var metricItems: [String] {
        metrics.map(LogTextFormatter.metricLine)
    }

    private var hasEntries: Bool {
        !meals.isEmpty || !workoutSets.isEmpty || !metrics.isEmpty
    }

    private var totalItems: Int {
        meals.count + workoutSets.count + metrics.count
    }

    private var isSparse: Bool {
        totalItems <= 3
    }

    var body: some View {
        Group {
            if hasEntries {
                if isSparse {
                    GeometryReader { geo in
                        contentStack
                            .padding(.horizontal, 24)
                            .padding(.top, geo.size.height * 0.38)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                } else {
                    ScrollView {
                        contentStack
                            .padding(.horizontal, 24)
                            .padding(.top, 24)
                            .padding(.bottom, 60)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text(dateString)
                        .smallCapsLabel(size: 12)
                    Text("Nothing yet today.")
                        .font(Typography.serifBody(17))
                        .foregroundStyle(Color.ledgerTextSecondary)
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .accessibilityIdentifier("todayLog.emptyState")
            }
        }
        .background(Color.ledgerBg)
    }

    private var contentStack: some View {
        VStack(alignment: .leading, spacing: 28) {
            header
            Rectangle()
                .fill(Color.ledgerHairline)
                .frame(height: 1)

            if !mealItems.isEmpty {
                section(title: "Eaten", items: mealItems)
            }
            if !workoutItems.isEmpty {
                section(title: "Trained", items: workoutItems, useRoundedNumbers: true)
            }
            if !metricItems.isEmpty {
                section(title: "Body", items: metricItems, useRoundedNumbers: true)
            }

            if !isSparse {
                Spacer(minLength: 40)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(dateString)
                .smallCapsLabel(size: 12)
            Text(caloriesString)
                .font(Typography.roundedNumber(44, weight: .semibold))
                .foregroundStyle(Color.ledgerTextPrimary)
            Text(proteinString)
                .font(Typography.roundedNumber(20, weight: .regular))
                .foregroundStyle(Color.ledgerTextSecondary)
        }
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("todayLog.totals")
    }

    @ViewBuilder
    private func section(title: String, items: [String], useRoundedNumbers: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .smallCapsLabel(size: 12)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(items, id: \.self) { item in
                    Button(action: {}) {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text("•")
                                .font(Typography.serifBody(16))
                                .foregroundStyle(Color.ledgerTextTertiary)
                            Text(item)
                                .font(useRoundedNumbers
                                      ? Typography.roundedNumber(16)
                                      : Typography.serifBody(16))
                                .foregroundStyle(Color.ledgerTextPrimary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(PressableRowStyle())
                }
            }
        }
    }
}

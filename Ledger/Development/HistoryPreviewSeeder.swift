import Foundation
import SwiftData

enum LedgerDevelopmentSeed: String {
    case historyPreview = "history_preview"
}

enum HistoryPreviewSeeder {
    @discardableResult
    static func seedIfNeeded(
        in modelContainer: ModelContainer,
        calendar: Calendar,
        now: Date
    ) throws -> Bool {
        let context = ModelContext(modelContainer)
        guard try !hasExistingData(in: context) else {
            return false
        }

        let baseDay = calendar.startOfDay(for: now)

        for day in days {
            let dayStart = calendar.date(byAdding: .day, value: -day.dayOffset, to: baseDay) ?? baseDay

            for meal in day.meals {
                context.insert(
                    StoredMeal(
                        date: dated(dayStart, hour: meal.hour, minute: meal.minute, calendar: calendar),
                        descriptionText: meal.description,
                        calories: meal.calories,
                        protein: meal.protein
                    )
                )
            }

            for workout in day.workouts {
                context.insert(
                    StoredWorkoutSet(
                        date: dated(dayStart, hour: workout.hour, minute: workout.minute, calendar: calendar),
                        exercise: workout.exercise,
                        summary: workout.summary,
                        notes: workout.notes
                    )
                )
            }

            for metric in day.metrics {
                context.insert(
                    StoredMetric(
                        date: dated(dayStart, hour: metric.hour, minute: metric.minute, calendar: calendar),
                        type: metric.type,
                        value: metric.value,
                        context: metric.context
                    )
                )
            }

            for message in day.messages {
                context.insert(
                    StoredMessage(
                        id: UUID(),
                        role: message.role,
                        content: message.content,
                        timestamp: dated(dayStart, hour: message.hour, minute: message.minute, calendar: calendar)
                    )
                )
            }
        }

        var identity = ""
        for (key, value) in identityFacts {
            identity = IdentityProfileDocument.upserting(key: key, value: value, into: identity)
        }
        context.insert(
            IdentityProfile(
                scope: IdentityProfile.defaultScope,
                markdownContent: identity,
                lastUpdated: now
            )
        )

        try context.save()
        return true
    }

    private static func hasExistingData(in context: ModelContext) throws -> Bool {
        let descriptors: [any PersistentModel.Type] = [
            StoredMessage.self,
            StoredMeal.self,
            StoredWorkoutSet.self,
            StoredMetric.self,
            IdentityProfile.self,
            Pattern.self,
            ActiveStateSnapshot.self,
            DailySummary.self,
            WeeklySummary.self,
            MonthlySummary.self
        ]

        for type in descriptors {
            if try hasRecords(of: type, in: context) {
                return true
            }
        }

        return false
    }

    private static func hasRecords(
        of type: any PersistentModel.Type,
        in context: ModelContext
    ) throws -> Bool {
        switch type {
        case is StoredMessage.Type:
            return try !context.fetch(FetchDescriptor<StoredMessage>()).isEmpty
        case is StoredMeal.Type:
            return try !context.fetch(FetchDescriptor<StoredMeal>()).isEmpty
        case is StoredWorkoutSet.Type:
            return try !context.fetch(FetchDescriptor<StoredWorkoutSet>()).isEmpty
        case is StoredMetric.Type:
            return try !context.fetch(FetchDescriptor<StoredMetric>()).isEmpty
        case is IdentityProfile.Type:
            return try !context.fetch(FetchDescriptor<IdentityProfile>()).isEmpty
        case is Pattern.Type:
            return try !context.fetch(FetchDescriptor<Pattern>()).isEmpty
        case is ActiveStateSnapshot.Type:
            return try !context.fetch(FetchDescriptor<ActiveStateSnapshot>()).isEmpty
        case is DailySummary.Type:
            return try !context.fetch(FetchDescriptor<DailySummary>()).isEmpty
        case is WeeklySummary.Type:
            return try !context.fetch(FetchDescriptor<WeeklySummary>()).isEmpty
        case is MonthlySummary.Type:
            return try !context.fetch(FetchDescriptor<MonthlySummary>()).isEmpty
        default:
            return false
        }
    }

    private static func dated(
        _ dayStart: Date,
        hour: Int,
        minute: Int,
        calendar: Calendar
    ) -> Date {
        calendar.date(
            bySettingHour: hour,
            minute: minute,
            second: 0,
            of: dayStart
        ) ?? dayStart
    }

    private static let identityFacts: [(String, String)] = [
        ("name", "Omar"),
        ("height", "183cm"),
        ("current_weight", "82.4kg"),
        ("goal_weight", "75kg"),
        ("goal_framing", "wants to rebuild his previously-trained 75kg physique after a 9-month break"),
        ("origin_story", "was lifting consistently until about 9 months ago, then fell off during a life transition"),
        ("approach", "moderate deficit, protein-forward eating, 3-4 lifting sessions per week"),
        ("calorie_target", "1900"),
        ("protein_target", "160"),
        ("goal_start_date", "2026-04-01"),
        ("shoulder_constraint", "tight right shoulder — keep overhead volume limited")
    ]

    private static let days: [DaySeed] = [
        DaySeed(
            dayOffset: 1,
            meals: [
                MealSeed(hour: 8, minute: 10, description: "Skyr, berries, granola", calories: 430, protein: 32),
                MealSeed(hour: 13, minute: 15, description: "Chicken shawarma bowl", calories: 820, protein: 58),
                MealSeed(hour: 20, minute: 25, description: "Steak, potatoes, side salad", calories: 760, protein: 54)
            ],
            workouts: [
                WorkoutSeed(hour: 18, minute: 12, exercise: "Bench press", summary: "4×6 @ 80kg", notes: "first time at 80 since the restart — felt solid"),
                WorkoutSeed(hour: 18, minute: 28, exercise: "Incline DB press", summary: "3×10 @ 32kg", notes: "last set slowed")
            ],
            metrics: [
                MetricSeed(hour: 7, minute: 2, type: "sleep", value: "7h 34m", context: nil),
                MetricSeed(hour: 7, minute: 3, type: "weight", value: "82.4kg", context: nil)
            ],
            messages: [
                MessageSeed(hour: 18, minute: 30, role: "user", content: "bench 4x6 @ 80 today, first time back at 80 since the restart"),
                MessageSeed(hour: 18, minute: 31, role: "coach", content: "That's a real checkpoint. Last time you benched 80 was pre-break. Muscle memory is doing its job.")
            ]
        ),
        DaySeed(
            dayOffset: 2,
            meals: [
                MealSeed(hour: 9, minute: 5, description: "Egg wrap and whey", calories: 510, protein: 47),
                MealSeed(hour: 13, minute: 35, description: "Sushi lunch set", calories: 690, protein: 34),
                MealSeed(hour: 20, minute: 40, description: "Turkey chili with rice", calories: 740, protein: 51)
            ],
            workouts: [],
            metrics: [
                MetricSeed(hour: 7, minute: 10, type: "sleep", value: "6h 41m", context: "restless")
            ]
        ),
        DaySeed(
            dayOffset: 3,
            meals: [
                MealSeed(hour: 12, minute: 20, description: "Protein bar and latte", calories: 340, protein: 23),
                MealSeed(hour: 19, minute: 50, description: "Burger and fries", calories: 980, protein: 42)
            ],
            workouts: [],
            metrics: [
                MetricSeed(hour: 7, minute: 10, type: "hrv", value: "24", context: "crashed after drinks"),
                MetricSeed(hour: 8, minute: 1, type: "mood", value: "flat", context: "feeling gross")
            ],
            messages: [
                MessageSeed(hour: 8, minute: 5, role: "user", content: "had like 4 beers with friends last night. HRV is 24 this morning and I feel gross, skipping the gym"),
                MessageSeed(hour: 8, minute: 6, role: "coach", content: "Right call. HRV crashed to 24 from a usual 30s — that's a 30% hit. Recovery day. Eat, hydrate, sleep. Don't pile a session on top."),
                MessageSeed(hour: 19, minute: 55, role: "user", content: "just got a burger and fries"),
                MessageSeed(hour: 19, minute: 56, role: "coach", content: "Fine. Body wants the salt and calories. Tomorrow is the real day.")
            ]
        ),
        DaySeed(
            dayOffset: 4,
            meals: [
                MealSeed(hour: 8, minute: 0, description: "Greek yogurt, banana, honey", calories: 390, protein: 29),
                MealSeed(hour: 14, minute: 2, description: "Double chicken burrito bowl", calories: 870, protein: 64),
                MealSeed(hour: 21, minute: 5, description: "Cottage cheese and fruit", calories: 280, protein: 26)
            ],
            workouts: [
                WorkoutSeed(hour: 18, minute: 18, exercise: "Low row", summary: "3×10 @ 68kg", notes: nil),
                WorkoutSeed(hour: 18, minute: 33, exercise: "Pullup", summary: "4×6 bw", notes: "clean reps")
            ],
            metrics: [
                MetricSeed(hour: 7, minute: 0, type: "hrv", value: "34", context: "back to baseline")
            ]
        ),
        DaySeed(
            dayOffset: 5,
            meals: [
                MealSeed(hour: 8, minute: 20, description: "Overnight oats", calories: 460, protein: 27),
                MealSeed(hour: 13, minute: 10, description: "2 Factor meals", calories: 1040, protein: 78),
                MealSeed(hour: 19, minute: 35, description: "Salmon, rice, greens", calories: 720, protein: 48)
            ],
            workouts: [],
            metrics: []
        ),
        DaySeed(
            dayOffset: 6,
            meals: [
                MealSeed(hour: 11, minute: 50, description: "Bagel, eggs, turkey bacon", calories: 640, protein: 39),
                MealSeed(hour: 20, minute: 15, description: "Chicken pesto pasta", calories: 880, protein: 52)
            ],
            workouts: [
                WorkoutSeed(hour: 17, minute: 42, exercise: "Romanian deadlift", summary: "3×8 @ 120kg", notes: "hamstrings cooked")
            ],
            metrics: [
                MetricSeed(hour: 7, minute: 8, type: "sleep", value: "8h 02m", context: nil)
            ]
        ),
        DaySeed(
            dayOffset: 7,
            meals: [
                MealSeed(hour: 10, minute: 15, description: "Hotel breakfast plate", calories: 780, protein: 36),
                MealSeed(hour: 15, minute: 5, description: "Chicken caesar wrap", calories: 620, protein: 38),
                MealSeed(hour: 21, minute: 0, description: "Late kebab plate", calories: 930, protein: 44)
            ],
            workouts: [],
            metrics: [
                MetricSeed(hour: 9, minute: 0, type: "weight", value: "82.9kg", context: "travel sodium")
            ]
        ),
        DaySeed(
            dayOffset: 8,
            meals: [
                MealSeed(hour: 8, minute: 5, description: "Skyr and cereal", calories: 410, protein: 30),
                MealSeed(hour: 13, minute: 20, description: "Chicken sandwich and soup", calories: 710, protein: 46),
                MealSeed(hour: 19, minute: 45, description: "Lean beef mince, rice, veg", calories: 760, protein: 56)
            ],
            workouts: [
                WorkoutSeed(hour: 18, minute: 8, exercise: "Hack squat", summary: "4×10 @ 120kg", notes: nil),
                WorkoutSeed(hour: 18, minute: 26, exercise: "Leg curl", summary: "3×12 @ 45kg", notes: nil)
            ],
            metrics: [
                MetricSeed(hour: 7, minute: 1, type: "hrv", value: "31", context: "slightly low")
            ]
        ),
        DaySeed(
            dayOffset: 9,
            meals: [
                MealSeed(hour: 12, minute: 0, description: "Protein shake and banana", calories: 260, protein: 31),
                MealSeed(hour: 19, minute: 30, description: "Pizza night", calories: 1250, protein: 48)
            ],
            workouts: [],
            metrics: [
                MetricSeed(hour: 8, minute: 5, type: "sleep", value: "5h 58m", context: "late night")
            ]
        ),
        DaySeed(
            dayOffset: 10,
            meals: [
                MealSeed(hour: 9, minute: 25, description: "Eggs on toast", calories: 470, protein: 28),
                MealSeed(hour: 13, minute: 45, description: "Chicken rice box", calories: 760, protein: 57),
                MealSeed(hour: 20, minute: 10, description: "Yogurt bowl", calories: 310, protein: 25)
            ],
            workouts: [
                WorkoutSeed(hour: 17, minute: 50, exercise: "Overhead press", summary: "5×5 @ 50kg", notes: "kept it light — right shoulder still a bit tight")
            ],
            metrics: [
                MetricSeed(hour: 7, minute: 6, type: "weight", value: "82.1kg", context: nil)
            ],
            messages: [
                MessageSeed(hour: 17, minute: 52, role: "user", content: "OHP 5x5 @ 50 — kept it light, shoulder still a bit tight"),
                MessageSeed(hour: 17, minute: 53, role: "coach", content: "Good read. No need to push the shoulder right now. Banking clean reps is the play.")
            ]
        ),
        DaySeed(
            dayOffset: 12,
            meals: [
                MealSeed(hour: 8, minute: 30, description: "Oats and whey", calories: 520, protein: 41),
                MealSeed(hour: 13, minute: 0, description: "Tuna melt", calories: 640, protein: 43),
                MealSeed(hour: 19, minute: 55, description: "Chicken fajitas", calories: 810, protein: 58)
            ],
            workouts: [],
            metrics: []
        ),
        DaySeed(
            dayOffset: 14,
            meals: [
                MealSeed(hour: 10, minute: 40, description: "Brunch plate", calories: 760, protein: 33),
                MealSeed(hour: 18, minute: 30, description: "Souvlaki wrap", calories: 690, protein: 41)
            ],
            workouts: [
                WorkoutSeed(hour: 16, minute: 42, exercise: "Cable row", summary: "3×12 @ 59kg", notes: nil),
                WorkoutSeed(hour: 16, minute: 58, exercise: "Lat pulldown", summary: "3×10 @ 63kg", notes: nil)
            ],
            metrics: [
                MetricSeed(hour: 7, minute: 4, type: "hrv", value: "29", context: "dragging")
            ]
        )
    ]
}

private struct DaySeed {
    let dayOffset: Int
    let meals: [MealSeed]
    let workouts: [WorkoutSeed]
    let metrics: [MetricSeed]
    let messages: [MessageSeed]

    init(
        dayOffset: Int,
        meals: [MealSeed],
        workouts: [WorkoutSeed],
        metrics: [MetricSeed],
        messages: [MessageSeed] = []
    ) {
        self.dayOffset = dayOffset
        self.meals = meals
        self.workouts = workouts
        self.metrics = metrics
        self.messages = messages
    }
}

private struct MessageSeed {
    let hour: Int
    let minute: Int
    let role: String
    let content: String
}

private struct MealSeed {
    let hour: Int
    let minute: Int
    let description: String
    let calories: Int
    let protein: Int
}

private struct WorkoutSeed {
    let hour: Int
    let minute: Int
    let exercise: String
    let summary: String
    let notes: String?
}

private struct MetricSeed {
    let hour: Int
    let minute: Int
    let type: String
    let value: String
    let context: String?
}

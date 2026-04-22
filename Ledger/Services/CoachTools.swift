import Foundation

struct Tool: Encodable, Sendable {
    let name: String
    let description: String
    let inputSchema: JSONValue
    let eagerInputStreaming: Bool

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case inputSchema = "input_schema"
        case eagerInputStreaming = "eager_input_streaming"
    }
}

enum CoachTools {
    static let all: [Tool] = [
        Tool(
            name: "update_meal_log",
            description: "Log a meal or food the user mentioned eating. Call this every time the user mentions eating something, even casually.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "description": .object([
                        "type": .string("string"),
                        "description": .string("Brief description of what was eaten, e.g. '2 Factor meals' or '8 cigköfte with lettuce'")
                    ]),
                    "estimated_calories": .object([
                        "type": .string("integer")
                    ]),
                    "estimated_protein_grams": .object([
                        "type": .string("integer")
                    ])
                ]),
                "required": .array([
                    .string("description"),
                    .string("estimated_calories"),
                    .string("estimated_protein_grams")
                ])
            ]),
            eagerInputStreaming: true
        ),
        Tool(
            name: "record_workout_set",
            description: "Record one or more sets of an exercise the user mentioned training.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "exercise": .object([
                        "type": .string("string"),
                        "description": .string("e.g. 'Bench press', 'Low row', 'Pullup'")
                    ]),
                    "summary": .object([
                        "type": .string("string"),
                        "description": .string("Formatted summary, e.g. '3×6 @ 50kg' or '3 sets → 60kg×8'")
                    ]),
                    "notes": .object([
                        "type": .string("string"),
                        "description": .string("Optional: how it felt, compared to prior")
                    ])
                ]),
                "required": .array([
                    .string("exercise"),
                    .string("summary")
                ])
            ]),
            eagerInputStreaming: true
        ),
        Tool(
            name: "update_metric",
            description: "Record a body/recovery metric the user shared.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "type": .object([
                        "type": .string("string"),
                        "enum": .array([
                            .string("hrv"),
                            .string("sleep"),
                            .string("weight"),
                            .string("mood"),
                            .string("other")
                        ])
                    ]),
                    "value": .object([
                        "type": .string("string"),
                        "description": .string("The value, e.g. '24', '7h 12m', '82.5kg'")
                    ]),
                    "context": .object([
                        "type": .string("string"),
                        "description": .string("Optional context, e.g. '(low)', 'after drinks'")
                    ])
                ]),
                "required": .array([
                    .string("type"),
                    .string("value")
                ])
            ]),
            eagerInputStreaming: true
        ),
        Tool(
            name: "update_profile",
            description: "Persist something the user revealed about themselves — a goal, constraint, preference, pattern. Only call for things worth remembering permanently.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "key": .object([
                        "type": .string("string"),
                        "description": .string("Short identifier, e.g. 'goal_weight', 'dietary_constraint', 'preferred_training_time'")
                    ]),
                    "value": .object([
                        "type": .string("string"),
                        "description": .string("The value to remember")
                    ])
                ]),
                "required": .array([
                    .string("key"),
                    .string("value")
                ])
            ]),
            eagerInputStreaming: true
        )
    ]
}

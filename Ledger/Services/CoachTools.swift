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
                    ]),
                    "evidence": .object([
                        "type": .string("string"),
                        "description": .string("A short verbatim quote from the CURRENT user message that supplies the food content being logged. Copy their exact words (e.g. 'had a burger for lunch', 'eggs and toast', '2 factor meals'). If the current message has no specific food content, do not fire this tool — do not fabricate a quote.")
                    ])
                ]),
                "required": .array([
                    .string("description"),
                    .string("estimated_calories"),
                    .string("estimated_protein_grams"),
                    .string("evidence")
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
                    ]),
                    "evidence": .object([
                        "type": .string("string"),
                        "description": .string("A short verbatim quote from the CURRENT user message that describes the training event. Copy their exact words (e.g. 'benched 80kg for 4x6', 'did 3 sets of deadlifts', 'pullups 10 8 6'). If the current message does not describe a training event that happened, do not fire this tool — do not fabricate a quote.")
                    ])
                ]),
                "required": .array([
                    .string("exercise"),
                    .string("summary"),
                    .string("evidence")
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
                    ]),
                    "evidence": .object([
                        "type": .string("string"),
                        "description": .string("A short verbatim quote from the CURRENT user message that supplies this metric value. Copy their exact words (e.g. 'hrv was 45', 'slept 7 hours', 'weight 82.5'). If the current message does not state a specific metric value, do not fire this tool — do not fabricate a quote.")
                    ])
                ]),
                "required": .array([
                    .string("type"),
                    .string("value"),
                    .string("evidence")
                ])
            ]),
            eagerInputStreaming: true
        ),
        Tool(
            name: "update_identity_fact",
            description: "Persist something about this person's identity — not just numeric facts but the way they frame their goal, the constraints they operate under, the approaches they've tried. Use this whenever you learn something that would change how you'd respond to them in the future.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "key": .object([
                        "type": .string("string"),
                        "description": .string("""
                        Short snake_case identifier. Atomic facts: name, age, height, current_weight, goal_weight, calorie_target, protein_target, goal_start_date. Framings (values can be multi-sentence): goal_framing (their language for their goal), origin_story (how they got to their current state), approach (their stated method). Constraints and preferences: constraint (dietary, medical, or practical limit), ruled_out (approach they've tried and won't repeat), preference (a stated preference worth honoring).
                        """)
                    ]),
                    "value": .object([
                        "type": .string("string"),
                        "description": .string("The fact, framing, or constraint to store. For framings, preserve the user's own language — do not paraphrase. Values for framing, constraint, ruled_out, and preference keys can be multi-sentence.")
                    ]),
                    "evidence": .object([
                        "type": .string("string"),
                        "description": .string("A short verbatim quote from the CURRENT user message that reveals this identity fact. Copy their exact words (e.g. 'my name is Marco', 'I want to lose 20 pounds', 'bad shoulder'). If the current message does not reveal anything new about who they are, do not fire this tool — do not fabricate a quote.")
                    ])
                ]),
                "required": .array([
                    .string("key"),
                    .string("value"),
                    .string("evidence")
                ])
            ]),
            eagerInputStreaming: true
        ),
        Tool(
            name: "search_archive",
            description: "Search older weekly and monthly summaries when the user asks about historical periods that are no longer in the loaded context.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "query": .object([
                        "type": .string("string"),
                        "description": .string("The historical topic or phrase to search for, e.g. 'last month', 'travel week', 'drinking'")
                    ])
                ]),
                "required": .array([
                    .string("query")
                ])
            ]),
            eagerInputStreaming: true
        )
    ]
}

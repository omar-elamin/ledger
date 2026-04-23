import XCTest
@testable import Ledger

final class CoachPromptTests: XCTestCase {
    func testPromptEncodesAntiChatbotVoiceConstraints() {
        let prompt = CoachPrompt.systemPrompt(
            contextBlock: """
            ## Who this person is
            ## Goals
            - goal_weight: 78kg

            ## Patterns observed
            Nothing notable yet.
            """
        )

        XCTAssertTrue(prompt.contains("Most replies should end on a statement, not a question."))
        XCTAssertTrue(prompt.contains("No emoticons or winks in text."))
        XCTAssertTrue(prompt.contains(#""What's next?""#))
        XCTAssertTrue(prompt.contains(#""Anything else?""#))
        XCTAssertTrue(prompt.contains(#""the app," "the system," "the database," or "the log""#))
        XCTAssertTrue(prompt.contains("Speak from within the relationship."))
        XCTAssertTrue(prompt.contains("Solid. That's roughly 1,200 cal and ~110g protein in the tank."))
        XCTAssertTrue(prompt.contains("search_archive"))
        XCTAssertFalse(prompt.contains("## First conversation"))
    }

    func testPromptIncludesGroundingSubsectionForToolUse() {
        let prompt = CoachPrompt.systemPrompt(
            contextBlock: """
            ## Who this person is
            ## Goals
            - goal_weight: 78kg
            """
        )

        XCTAssertTrue(prompt.contains("## Grounding tool calls"))
        XCTAssertTrue(prompt.contains("requires an `evidence` field"))
        XCTAssertTrue(prompt.contains("verbatim quote from the CURRENT user message"))
        XCTAssertTrue(prompt.contains("Do not paraphrase. Do not invent."))
        XCTAssertTrue(prompt.contains("A day with no logged workouts because the user skipped"))
    }

    func testPromptIncludesResolvingContradictionsSubsection() {
        let prompt = CoachPrompt.systemPrompt(
            contextBlock: """
            ## Who this person is
            ## Goals
            - goal_weight: 78kg
            """
        )

        XCTAssertTrue(prompt.contains("## Resolving contradictions"))
        XCTAssertTrue(prompt.contains(#""Regular or veggie?""#))
        XCTAssertTrue(prompt.contains("not substitutes for the user's own words"))
    }

    func testPromptInjectsFirstConversationSectionWhenIdentityIsPlaceholder() {
        let prompt = CoachPrompt.systemPrompt(
            contextBlock: """
            ## Who this person is
            No stable identity facts recorded yet.

            ## Patterns observed
            None yet.
            """
        )

        XCTAssertTrue(prompt.contains("## First conversation"))
        XCTAssertTrue(prompt.contains("Call update_identity_fact silently as you learn things."))
        XCTAssertTrue(prompt.contains(#""Hi. What should I call you?""#))
    }

    func testFirstConversationIncludesWhatToAvoidSubsection() {
        let prompt = CoachPrompt.systemPrompt(
            contextBlock: """
            ## Who this person is
            No stable identity facts recorded yet.
            """
        )

        XCTAssertTrue(prompt.contains("### What to avoid"))
        XCTAssertTrue(prompt.contains("**Compound questions.**"))
        XCTAssertTrue(prompt.contains("**Enumerated options.**"))
        XCTAssertTrue(prompt.contains(#"Wrong: "Nice to meet you, Marco. How much do you weigh now, and how"#))
        XCTAssertTrue(prompt.contains(#"Right: "What's going on with you?""#))
    }

    func testPromptSkipsFirstConversationSectionWhenIdentityContainsFacts() {
        let prompt = CoachPrompt.systemPrompt(
            contextBlock: """
            ## Who this person is
            ## Body
            - height: 5'11
            - weight: 210

            ## Goals
            - goal_weight: 190
            """
        )

        XCTAssertFalse(prompt.contains("## First conversation"))
    }
}

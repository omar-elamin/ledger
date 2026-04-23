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

import XCTest
@testable import Ledger

final class CoachPromptTests: XCTestCase {
    func testPromptEncodesAntiChatbotVoiceConstraints() {
        let prompt = CoachPrompt.systemPrompt(
            profile: "Cuts fast when routine is tight.",
            weeklyContext: "",
            todayLog: "No meals logged."
        )

        XCTAssertTrue(prompt.contains("Most replies should end on a statement, not a question."))
        XCTAssertTrue(prompt.contains("No emoticons or winks in text."))
        XCTAssertTrue(prompt.contains(#""What's next?""#))
        XCTAssertTrue(prompt.contains(#""Anything else?""#))
        XCTAssertTrue(prompt.contains(#""the app," "the system," "the database," or "the log""#))
        XCTAssertTrue(prompt.contains("Speak from within the relationship."))
        XCTAssertTrue(prompt.contains("Solid. That's roughly 1,200 cal and ~110g protein in the tank."))
    }
}

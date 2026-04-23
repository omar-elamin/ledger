import XCTest
@testable import Ledger

final class IdentityProfileDocumentTests: XCTestCase {
    func testUpsertingRoutesFactsIntoExpectedSections() {
        let markdown = IdentityProfileDocument.merging(
            markdown: "",
            with: [
                (key: "goal_weight", value: "78kg"),
                (key: "weight", value: "81.8kg"),
                (key: "training_time", value: "evenings"),
                (key: "travel_schedule", value: "weekly")
            ]
        )

        let sections = IdentityProfileDocument.sections(from: markdown)

        XCTAssertEqual(sections["Goals"]?["goal_weight"], "78kg")
        XCTAssertEqual(sections["Body"]?["weight"], "81.8kg")
        XCTAssertEqual(sections["Preferences"]?["training_time"], "evenings")
        XCTAssertEqual(sections["Lifestyle"]?["travel_schedule"], "weekly")
    }

    func testUpsertingMovesExistingKeyBetweenSections() {
        let initial = IdentityProfileDocument.upserting(
            key: "training_time",
            value: "mornings",
            into: ""
        )
        let moved = IdentityProfileDocument.upserting(
            key: "goal_training_time",
            value: "evenings",
            into: initial
        )

        let sections = IdentityProfileDocument.sections(from: moved)

        XCTAssertNil(sections["Preferences"]?["goal_training_time"])
        XCTAssertEqual(sections["Goals"]?["goal_training_time"], "evenings")
        XCTAssertEqual(sections["Preferences"]?["training_time"], "mornings")
    }

    func testUpsertingNormalizesMultilineValues() {
        let markdown = IdentityProfileDocument.upserting(
            key: "dietary_constraint",
            value: "\n  lactose intolerant \n needs low-fat dairy \n",
            into: ""
        )

        XCTAssertEqual(
            IdentityProfileDocument.facts(from: markdown)["dietary_constraint"],
            "lactose intolerant needs low-fat dairy"
        )
    }

    func testFactsReturnsFlattenedLatestValues() {
        let markdown = """
        ## Goals
        - goal_weight: 78kg

        ## Preferences
        - training_time: evenings
        """

        let facts = IdentityProfileDocument.facts(from: markdown)

        XCTAssertEqual(facts["goal_weight"], "78kg")
        XCTAssertEqual(facts["training_time"], "evenings")
        XCTAssertEqual(facts.count, 2)
    }
}

import XCTest

final class LedgerUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testFirstLaunchShowsSeedMessage() {
        let app = launchApp(storePath: makeStorePath())

        XCTAssertTrue(
            staticText(containing: "What's going on with you?", in: app)
                .waitForExistence(timeout: 5)
        )
    }

    func testPlainChatSendShowsCoachReply() {
        let app = launchApp(storePath: makeStorePath())

        send("Yo", in: app)

        XCTAssertTrue(
            staticText(containing: "What are we actually solving today?", in: app)
                .waitForExistence(timeout: 5)
        )
    }

    func testMealMessageUpdatesTodayLog() {
        let app = launchApp(storePath: makeStorePath())

        send("had 2 factor meals and 200g of chicken", in: app)

        XCTAssertTrue(
            staticText(containing: "1,200 cal", in: app)
                .waitForExistence(timeout: 5)
        )

        app.swipeRight()

        XCTAssertTrue(
            staticText(containing: "2 Factor meals + 200g chicken", in: app)
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            staticText(containing: "1200 cal", in: app)
                .waitForExistence(timeout: 5)
        )
    }

    func testHistoryShowsRolledUpDayAfterLogging() {
        let app = launchApp(storePath: makeStorePath())

        send("had 2 factor meals and 200g of chicken", in: app)

        XCTAssertTrue(
            staticText(containing: "Good protein floor for the day.", in: app)
                .waitForExistence(timeout: 5)
        )

        app.swipeLeft()

        XCTAssertTrue(
            app.descendants(matching: .any)["history.daySummary.2026-04-22"]
                .waitForExistence(timeout: 5)
        )
    }

    func testChatAndTodayLogPersistAcrossRelaunch() {
        let storePath = makeStorePath()
        let app = launchApp(storePath: storePath)

        send("had 2 factor meals and 200g of chicken", in: app)
        XCTAssertTrue(
            staticText(containing: "1,200 cal", in: app)
                .waitForExistence(timeout: 5)
        )

        app.terminate()

        let relaunched = launchApp(storePath: storePath)

        XCTAssertTrue(
            staticText(containing: "2 factor meals and 200g of chicken", in: relaunched)
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            staticText(containing: "Good protein floor for the day.", in: relaunched)
                .waitForExistence(timeout: 5)
        )

        relaunched.swipeRight()
        XCTAssertTrue(
            staticText(containing: "2 Factor meals + 200g chicken", in: relaunched)
                .waitForExistence(timeout: 5)
        )
    }

    private func launchApp(storePath: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["LEDGER_TEST_MODE"] = "1"
        app.launchEnvironment["LEDGER_TEST_SCENARIO"] = "happy_path"
        app.launchEnvironment["LEDGER_TEST_STORE_PATH"] = storePath
        app.launchEnvironment["LEDGER_TEST_NOW_ISO8601"] = "2026-04-22T12:00:00Z"
        app.launch()
        return app
    }

    private func send(_ text: String, in app: XCUIApplication) {
        let input = app.descendants(matching: .any)["chat.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText(text + "\n")
    }

    private func staticText(containing substring: String, in app: XCUIApplication) -> XCUIElement {
        app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS %@", substring)
        ).firstMatch
    }

    private func makeStorePath() -> String {
        "/tmp/ledger-ui-tests/\(UUID().uuidString).store"
    }
}

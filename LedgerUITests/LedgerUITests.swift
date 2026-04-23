import Foundation
import XCTest

final class LedgerUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testFirstLaunchShowsSeedMessage() {
        let fixture = UITestFixture()
        let app = launchApp(fixture: fixture)

        XCTAssertTrue(
            staticText(containing: "What should I call you?", in: app)
                .waitForExistence(timeout: 5)
        )
    }

    func testPlainChatSendShowsCoachReply() {
        let fixture = UITestFixture()
        let app = launchApp(fixture: fixture)

        send("Yo", in: app)

        XCTAssertTrue(
            staticText(containing: "Tell me what's actually going on.", in: app)
                .waitForExistence(timeout: 5)
        )
    }

    func testMealMessageUpdatesTodayLog() {
        let fixture = UITestFixture()
        let app = launchApp(fixture: fixture)

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
        let fixture = UITestFixture()
        let app = launchApp(fixture: fixture)

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
        let fixture = UITestFixture()
        let app = launchApp(fixture: fixture)

        send("had 2 factor meals and 200g of chicken", in: app)
        XCTAssertTrue(
            staticText(containing: "1,200 cal", in: app)
                .waitForExistence(timeout: 5)
        )

        app.terminate()

        let relaunched = launchApp(fixture: fixture)

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

    func testMemoryHarnessCanRunNightlyAndDumpSnapshot() throws {
        let fixture = UITestFixture()
        let app = launchApp(fixture: fixture)

        tapHarnessButton("testHarness.runNightlyButton", waitingFor: "nightly:success", in: app)
        tapHarnessButton("testHarness.dumpSnapshotButton", waitingFor: "snapshot:success", in: app)

        let snapshot = try readSnapshot(at: fixture.snapshotPath)
        XCTAssertNotNil(snapshot.activeStateSnapshot)
        XCTAssertEqual(snapshot.dailySummaries.count, 1)
        XCTAssertEqual(snapshot.nowISO8601, "2026-04-22T12:00:00Z")
    }
}

final class HierarchicalMemoryE2ETests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testIdentityAndPatternsAccrueAcrossDaysAndPersist() throws {
        try requireMemoryE2E()

        let fixture = UITestFixture(nowISO8601: "2026-04-20T12:00:00Z")
        let app = launchApp(fixture: fixture)

        send("I want to cut to 78kg.", in: app)
        XCTAssertTrue(
            staticText(containing: "Noted. That's the number", in: app)
                .waitForExistence(timeout: 5)
        )
        send("Went out with friends and drank. Protein was light.", in: app)
        waitForStreamingToFinish(in: app)
        tapHarnessButton("testHarness.runNightlyButton", waitingFor: "nightly:success", in: app)

        replaceText(in: app.descendants(matching: .any)["testHarness.advanceDaysInput"], with: "1")
        tapHarnessButton("testHarness.advanceDaysButton", waitingFor: "time:advanced", in: app)
        send("Went out with friends again and protein was light.", in: app)
        waitForStreamingToFinish(in: app)
        tapHarnessButton("testHarness.runNightlyButton", waitingFor: "nightly:success", in: app)

        replaceText(in: app.descendants(matching: .any)["testHarness.advanceDaysInput"], with: "1")
        tapHarnessButton("testHarness.advanceDaysButton", waitingFor: "time:advanced", in: app)
        send("Another social night. Protein was light again.", in: app)
        waitForStreamingToFinish(in: app)
        tapHarnessButton("testHarness.runNightlyButton", waitingFor: "nightly:success", in: app)

        replaceText(in: app.descendants(matching: .any)["testHarness.advanceDaysInput"], with: "4")
        tapHarnessButton("testHarness.advanceDaysButton", waitingFor: "time:advanced", in: app)
        send("Bench 3x5 @ 100kg", in: app)
        waitForStreamingToFinish(in: app)
        send("Weight this morning was 81.8kg", in: app)
        waitForStreamingToFinish(in: app)
        tapHarnessButton("testHarness.runNightlyButton", waitingFor: "nightly:success", in: app)

        send("What do you know about me?", in: app)
        XCTAssertTrue(
            staticText(containing: "goal_weight: 78kg", in: app)
                .waitForExistence(timeout: 5)
        )

        send("What pattern do you see?", in: app)
        XCTAssertTrue(
            staticText(containing: "Protein tends to lag on social days.", in: app)
                .waitForExistence(timeout: 5)
        )

        tapHarnessButton("testHarness.dumpSnapshotButton", waitingFor: "snapshot:success", in: app)
        let snapshot = try readSnapshot(at: fixture.snapshotPath)
        XCTAssertEqual(snapshot.identityProfile?.sections["Goals"]?["goal_weight"], "78kg")
        XCTAssertTrue(snapshot.patterns.contains(where: { $0.key == "protein_social_days" }))
        XCTAssertTrue(snapshot.dailySummaries.count >= 3)
        XCTAssertTrue(snapshot.activeStateSnapshot?.markdownContent.contains("Bench press: 100kg") == true)

        app.terminate()
        let relaunched = launchApp(fixture: fixture)
        send("What do you know about me?", in: relaunched)
        XCTAssertTrue(
            staticText(containing: "goal_weight: 78kg", in: relaunched)
                .waitForExistence(timeout: 5)
        )
    }

    func testArchiveRollupSupportsHistoricalQuestion() throws {
        try requireMemoryE2E()

        let fixture = UITestFixture(nowISO8601: "2026-03-01T12:00:00Z")
        let app = launchApp(fixture: fixture)

        send("Travel week with poor sleep.", in: app)
        waitForStreamingToFinish(in: app)
        tapHarnessButton("testHarness.runNightlyButton", waitingFor: "nightly:success", in: app)

        replaceText(in: app.descendants(matching: .any)["testHarness.advanceDaysInput"], with: "1")
        tapHarnessButton("testHarness.advanceDaysButton", waitingFor: "time:advanced", in: app)
        send("Travel continued and meals got loose.", in: app)
        waitForStreamingToFinish(in: app)
        tapHarnessButton("testHarness.runNightlyButton", waitingFor: "nightly:success", in: app)

        replaceText(in: app.descendants(matching: .any)["testHarness.nowInput"], with: "2026-04-22T12:00:00Z")
        tapHarnessButton("testHarness.setNowButton", waitingFor: "time:set", in: app)
        tapHarnessButton("testHarness.runNightlyButton", waitingFor: "nightly:success", in: app)
        tapHarnessButton("testHarness.dumpSnapshotButton", waitingFor: "snapshot:success", in: app)

        let snapshot = try readSnapshot(at: fixture.snapshotPath)
        XCTAssertTrue(snapshot.monthlySummaries.count >= 1)
        XCTAssertTrue(snapshot.monthlySummaries.first?.summaryText.lowercased().contains("travel") == true)

        send("How was last month?", in: app)
        XCTAssertTrue(
            staticText(containing: "Last month in one line:", in: app)
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            staticText(containing: "travel", in: app)
                .waitForExistence(timeout: 5)
        )
    }

    private func requireMemoryE2E() throws {
        guard ProcessInfo.processInfo.environment["LEDGER_RUN_MEMORY_E2E"] == "1" else {
            throw XCTSkip("Set LEDGER_RUN_MEMORY_E2E=1 to run the heavy memory E2E suite.")
        }
    }
}

private struct UITestFixture {
    let storePath: String
    let defaultsSuite: String
    let snapshotPath: String
    let nowISO8601: String

    init(nowISO8601: String = "2026-04-22T12:00:00Z") {
        let base = "/tmp/ledger-ui-tests/\(UUID().uuidString)"
        self.storePath = "\(base).store"
        self.defaultsSuite = "LedgerUITests.\(UUID().uuidString)"
        self.snapshotPath = "\(base).json"
        self.nowISO8601 = nowISO8601
    }
}

private struct MemorySnapshotFile: Decodable {
    let nowISO8601: String
    let identityProfile: IdentityProfileFile?
    let patterns: [PatternFile]
    let activeStateSnapshot: ActiveStateFile?
    let dailySummaries: [SummaryFile]
    let weeklySummaries: [SummaryFile]
    let monthlySummaries: [SummaryFile]
}

private struct IdentityProfileFile: Decodable {
    let markdownContent: String
    let sections: [String: [String: String]]
}

private struct PatternFile: Decodable {
    let key: String
    let descriptionText: String
}

private struct ActiveStateFile: Decodable {
    let markdownContent: String
}

private struct SummaryFile: Decodable {
    let summaryText: String
}

private func launchApp(fixture: UITestFixture) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchEnvironment["LEDGER_TEST_MODE"] = "1"
    app.launchEnvironment["LEDGER_TEST_COACH_SCENARIO"] = "happy_path"
    app.launchEnvironment["LEDGER_TEST_MEMORY_SCENARIO"] = "deterministic"
    app.launchEnvironment["LEDGER_TEST_STORE_PATH"] = fixture.storePath
    app.launchEnvironment["LEDGER_TEST_DEFAULTS_SUITE"] = fixture.defaultsSuite
    app.launchEnvironment["LEDGER_TEST_SNAPSHOT_PATH"] = fixture.snapshotPath
    app.launchEnvironment["LEDGER_TEST_NOW_ISO8601"] = fixture.nowISO8601
    if let runMemoryE2E = ProcessInfo.processInfo.environment["LEDGER_RUN_MEMORY_E2E"] {
        app.launchEnvironment["LEDGER_RUN_MEMORY_E2E"] = runMemoryE2E
    }
    app.launch()
    return app
}

private func send(_ text: String, in app: XCUIApplication) {
    let input = app.descendants(matching: .any)["chat.input"]
    XCTAssertTrue(input.waitForExistence(timeout: 5))
    input.tap()
    input.typeText(text + "\n")
}

private func tapHarnessButton(
    _ identifier: String,
    waitingFor status: String,
    in app: XCUIApplication
) {
    let button = app.descendants(matching: .any)[identifier]
    XCTAssertTrue(button.waitForExistence(timeout: 5))
    let statusLabel = app.descendants(matching: .any)["testHarness.status"]
    XCTAssertTrue(statusLabel.waitForExistence(timeout: 5))

    button.tap()

    if let currentLabel = statusLabel.label as String?, currentLabel == status {
        let changedPredicate = NSPredicate(format: "label != %@", status)
        let changedExpectation = XCTNSPredicateExpectation(predicate: changedPredicate, object: statusLabel)
        _ = XCTWaiter.wait(for: [changedExpectation], timeout: 1)
    }

    let predicate = NSPredicate(format: "label == %@", status)
    let expectation = XCTNSPredicateExpectation(predicate: predicate, object: statusLabel)
    XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed)
}

private func replaceText(in element: XCUIElement, with value: String) {
    XCTAssertTrue(element.waitForExistence(timeout: 5))
    element.tap()

    if
        let stringValue = element.value as? String,
        !stringValue.isEmpty,
        stringValue != "ISO8601",
        stringValue != "Days"
    {
        let deleteString = String(repeating: XCUIKeyboardKey.delete.rawValue, count: stringValue.count)
        element.typeText(deleteString)
    }

    element.typeText(value)
}

private func staticText(containing substring: String, in app: XCUIApplication) -> XCUIElement {
    app.staticTexts.containing(
        NSPredicate(format: "label CONTAINS[c] %@", substring)
    ).firstMatch
}

private func waitForStreamingToFinish(in app: XCUIApplication) {
    let bubble = app.descendants(matching: .any)["chat.streamingBubble"]
    let predicate = NSPredicate(format: "exists == false")
    let expectation = XCTNSPredicateExpectation(predicate: predicate, object: bubble)
    XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed)
}

private func readSnapshot(at path: String) throws -> MemorySnapshotFile {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    return try JSONDecoder().decode(MemorySnapshotFile.self, from: data)
}

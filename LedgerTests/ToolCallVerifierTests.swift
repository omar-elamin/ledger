import Foundation
import XCTest
@testable import Ledger

final class ToolCallVerifierTests: XCTestCase {

    private var capturedWrites: [(URL, Data)] = []
    private var originalWriter: ((URL, Data) throws -> Void)!

    override func setUp() {
        super.setUp()
        originalWriter = ToolCallVerifier.logWriter
        capturedWrites = []
        ToolCallVerifier.logWriter = { [self] url, data in
            capturedWrites.append((url, data))
        }
    }

    override func tearDown() {
        ToolCallVerifier.logWriter = originalWriter
        super.tearDown()
    }

    // MARK: - verify() — evidence must appear in user message

    func testEvidencePresentAndQuotedAllows() {
        let verdict = ToolCallVerifier.verify(
            toolName: "update_meal_log",
            rawJSON: #"{"description":"burger","estimated_calories":700,"estimated_protein_grams":35,"evidence":"had a burger for lunch"}"#,
            userMessage: "had a burger for lunch, was solid"
        )
        XCTAssertEqual(verdict, .allow)
    }

    func testEvidenceAbsentBlocks() {
        let verdict = ToolCallVerifier.verify(
            toolName: "record_workout_set",
            rawJSON: #"{"exercise":"Bench press","summary":"4×6 @ 80kg"}"#,
            userMessage: "fucked up today. skipped the gym, ate shit all day"
        )
        guard case .block(let reason) = verdict else {
            XCTFail("Expected .block for missing evidence, got \(verdict)")
            return
        }
        XCTAssertEqual(reason, "tool call missing required evidence quote")
    }

    func testEvidenceEmptyBlocks() {
        let verdict = ToolCallVerifier.verify(
            toolName: "update_meal_log",
            rawJSON: #"{"description":"x","estimated_calories":1,"estimated_protein_grams":1,"evidence":""}"#,
            userMessage: "had a burger"
        )
        guard case .block(let reason) = verdict else {
            XCTFail("Expected .block for empty evidence, got \(verdict)")
            return
        }
        XCTAssertEqual(reason, "evidence quote is empty")
    }

    func testFabricatedEvidenceBlocks() {
        // Model hallucinates an evidence string that isn't in the user message.
        let verdict = ToolCallVerifier.verify(
            toolName: "record_workout_set",
            rawJSON: #"{"exercise":"Bench press","summary":"4×6 @ 80kg","evidence":"benched 80kg for 4x6"}"#,
            userMessage: "fucked up today. skipped the gym, ate shit all day, drank last night"
        )
        guard case .block(let reason) = verdict else {
            XCTFail("Expected .block for fabricated evidence, got \(verdict)")
            return
        }
        XCTAssertEqual(reason, "evidence quote not found in user message")
    }

    func testScenarioEBlocksEitherWay() {
        // Model might try: (a) omit evidence, (b) fabricate one, (c) quote a fragment like "today".
        // (a) and (b) are covered above. (c) — a tiny unrelated fragment — is still a concern
        // but at least the model had to commit to a quote instead of hiding behind keywords.
        // Here we verify the most common failure: the model quotes something from the message
        // that doesn't actually describe a workout. This ISN'T blocked by the verifier alone —
        // it's caught by the prompt ("no quote in this message that supplies a workout").
        // The verifier's job is narrower: reject fabrications and omissions.
        let omittedEvidence = ToolCallVerifier.verify(
            toolName: "record_workout_set",
            rawJSON: #"{"exercise":"Bench press","summary":"4×6 @ 80kg","notes":"First time at 80kg since restart"}"#,
            userMessage: "fucked up today. skipped the gym, ate shit all day, drank last night"
        )
        guard case .block = omittedEvidence else {
            XCTFail("Scenario E with no evidence should be blocked")
            return
        }

        let fabricatedEvidence = ToolCallVerifier.verify(
            toolName: "record_workout_set",
            rawJSON: #"{"exercise":"Bench press","summary":"4×6 @ 80kg","evidence":"benched 80kg for 4 sets"}"#,
            userMessage: "fucked up today. skipped the gym, ate shit all day, drank last night"
        )
        guard case .block = fabricatedEvidence else {
            XCTFail("Scenario E with fabricated evidence should be blocked")
            return
        }
    }

    // MARK: - verify() — normalization (apostrophes, case, whitespace)

    func testEvidenceCaseInsensitive() {
        let verdict = ToolCallVerifier.verify(
            toolName: "update_meal_log",
            rawJSON: #"{"description":"x","estimated_calories":1,"estimated_protein_grams":1,"evidence":"HAD A BURGER"}"#,
            userMessage: "had a burger for lunch"
        )
        XCTAssertEqual(verdict, .allow)
    }

    func testEvidenceSmartApostropheMatchesAsciiAndViceVersa() {
        // Evidence has smart apostrophe, message has ASCII → match.
        let v1 = ToolCallVerifier.verify(
            toolName: "record_workout_set",
            rawJSON: #"{"exercise":"x","summary":"x","evidence":"didn’t miss a rep"}"#,
            userMessage: "benched 80kg and didn't miss a rep"
        )
        XCTAssertEqual(v1, .allow)

        // Evidence has ASCII, message has smart apostrophe → match.
        let v2 = ToolCallVerifier.verify(
            toolName: "record_workout_set",
            rawJSON: #"{"exercise":"x","summary":"x","evidence":"didn't miss a rep"}"#,
            userMessage: "benched 80kg and didn\u{2019}t miss a rep"
        )
        XCTAssertEqual(v2, .allow)
    }

    func testEvidenceWhitespaceCollapsed() {
        let verdict = ToolCallVerifier.verify(
            toolName: "update_meal_log",
            rawJSON: #"{"description":"x","estimated_calories":1,"estimated_protein_grams":1,"evidence":"  had   a    burger  "}"#,
            userMessage: "had a burger for lunch"
        )
        XCTAssertEqual(verdict, .allow)
    }

    // MARK: - verify() — non-write tools always allow

    func testSearchArchiveAlwaysAllowsEvenWithoutEvidence() {
        let verdict = ToolCallVerifier.verify(
            toolName: "search_archive",
            rawJSON: #"{"query":"travel"}"#,
            userMessage: nil
        )
        XCTAssertEqual(verdict, .allow)
    }

    // MARK: - verify() — empty message

    func testEmptyUserMessageFlagsNotBlocks() {
        let verdict = ToolCallVerifier.verify(
            toolName: "record_workout_set",
            rawJSON: #"{"exercise":"x","summary":"x","evidence":"anything"}"#,
            userMessage: ""
        )
        if case .flag(let reason) = verdict {
            XCTAssertEqual(reason, "no user message captured")
        } else {
            XCTFail("Expected .flag for empty message, got \(verdict)")
        }
    }

    // MARK: - verify() — covers all four write tools uniformly

    func testUpdateMetricRequiresEvidence() {
        let without = ToolCallVerifier.verify(
            toolName: "update_metric",
            rawJSON: #"{"type":"weight","value":"82kg"}"#,
            userMessage: "feeling tired today"
        )
        guard case .block = without else {
            XCTFail("update_metric without evidence must block")
            return
        }

        let with = ToolCallVerifier.verify(
            toolName: "update_metric",
            rawJSON: #"{"type":"hrv","value":"45","evidence":"hrv was 45"}"#,
            userMessage: "hrv was 45 this morning"
        )
        XCTAssertEqual(with, .allow)
    }

    func testUpdateIdentityFactRequiresEvidence() {
        let fabricated = ToolCallVerifier.verify(
            toolName: "update_identity_fact",
            rawJSON: #"{"key":"goal_weight","value":"75kg","evidence":"goal is 75kg"}"#,
            userMessage: "fine, whatever"
        )
        guard case .block = fabricated else {
            XCTFail("Fabricated identity evidence must block")
            return
        }

        let grounded = ToolCallVerifier.verify(
            toolName: "update_identity_fact",
            rawJSON: #"{"key":"name","value":"Marco","evidence":"my name is Marco"}"#,
            userMessage: "hey, my name is Marco"
        )
        XCTAssertEqual(grounded, .allow)
    }

    // MARK: - Log writer

    func testAppendLogWritesEncodedEntryForBlock() throws {
        ToolCallVerifier.appendLog(
            toolName: "record_workout_set",
            rawJSON: #"{"exercise":"Bench"}"#,
            userMessage: "skipped the gym",
            verdict: "blocked",
            reason: "tool call missing required evidence quote"
        )

        XCTAssertEqual(capturedWrites.count, 1)
        let (_, data) = try XCTUnwrap(capturedWrites.first)
        let line = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(line.hasSuffix("\n"))
        let decoded = try JSONDecoder().decode([String: String].self, from: Data(
            line.trimmingCharacters(in: .whitespacesAndNewlines).utf8
        ))
        XCTAssertEqual(decoded["toolName"], "record_workout_set")
        XCTAssertEqual(decoded["verdict"], "blocked")
        XCTAssertNotNil(decoded["date"])
    }

    func testAppendLogSurvivesWriterError() {
        struct WriterError: Error {}
        ToolCallVerifier.logWriter = { _, _ in throw WriterError() }

        // Must not throw or crash.
        ToolCallVerifier.appendLog(
            toolName: "record_workout_set",
            rawJSON: "{}",
            userMessage: "msg",
            verdict: "blocked",
            reason: "reason"
        )
    }

    func testDefaultLogWriterCreatesDirectoryAndAppends() throws {
        let tempBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("ledger-tests-\(UUID().uuidString)", isDirectory: true)
        let logURL = tempBase.appendingPathComponent("Ledger/tool-verifier.jsonl")

        defer { try? FileManager.default.removeItem(at: tempBase) }

        let savedURL = ToolCallVerifier.logFileURL
        let savedWriter = ToolCallVerifier.logWriter
        ToolCallVerifier.logFileURL = logURL
        ToolCallVerifier.logWriter = ToolCallVerifier.makeDefaultLogWriterForTesting()
        defer {
            ToolCallVerifier.logFileURL = savedURL
            ToolCallVerifier.logWriter = savedWriter
        }

        ToolCallVerifier.appendLog(
            toolName: "record_workout_set",
            rawJSON: "{}", userMessage: "a", verdict: "blocked", reason: "r"
        )
        ToolCallVerifier.appendLog(
            toolName: "update_meal_log",
            rawJSON: "{}", userMessage: "b", verdict: "blocked", reason: "r"
        )

        let contents = try String(contentsOf: logURL, encoding: .utf8)
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: true)
        XCTAssertEqual(lines.count, 2)
    }
}

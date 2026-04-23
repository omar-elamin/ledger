import Foundation
import OSLog

// Grounds write tool calls in the current user message. Every write tool must
// include a verbatim quote from the current user message as `evidence`. Swift
// checks that the quote actually appears in the message (normalized for case,
// whitespace, and smart apostrophes). If not, the write is blocked before it
// reaches SwiftData.
//
// Origin: Scenario E (docs/qa/2026-04-23/FINDINGS.md) — coach fired
// record_workout_set with yesterday's bench session after user said
// "skipped the gym." Keyword heuristics were considered and rejected
// (brittle, leaky, require maintenance); evidence-quote verification
// offloads judgment to the LLM and does a deterministic check in Swift.

enum ToolCallVerdict: Equatable {
    case allow
    case flag(reason: String)
    case block(reason: String)
}

enum ToolCallVerifier {
    private static let logger = Logger(subsystem: "com.omarelamin.ledger", category: "ToolCallVerifier")

    static let writeTools: Set<String> = [
        "record_workout_set",
        "update_meal_log",
        "update_metric",
        "update_identity_fact"
    ]

    static func verify(toolName: String, rawJSON: String, userMessage: String?) -> ToolCallVerdict {
        guard writeTools.contains(toolName) else {
            return .allow
        }

        guard let normalizedMessage = normalize(userMessage) else {
            return .flag(reason: "no user message captured")
        }

        guard let evidence = extractEvidence(from: rawJSON) else {
            return .block(reason: "tool call missing required evidence quote")
        }

        guard let normalizedEvidence = normalize(evidence), !normalizedEvidence.isEmpty else {
            return .block(reason: "evidence quote is empty")
        }

        if normalizedMessage.contains(normalizedEvidence) {
            return .allow
        }
        return .block(reason: "evidence quote not found in user message")
    }

    // MARK: - Normalization

    /// Lowercases, folds smart apostrophes to ASCII, and collapses internal whitespace
    /// so `"didn\u{2019}t go"` and `"Didn't  go"` compare equal.
    static func normalize(_ raw: String?) -> String? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let folded = trimmed
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
        let lowercased = folded.lowercased()
        let collapsedWhitespace = lowercased
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return collapsedWhitespace
    }

    private static func extractEvidence(from rawJSON: String) -> String? {
        guard let data = rawJSON.data(using: .utf8) else { return nil }
        do {
            let decoded = try JSONSerialization.jsonObject(with: data)
            if let dict = decoded as? [String: Any], let ev = dict["evidence"] as? String {
                return ev
            }
        } catch {
            return nil
        }
        return nil
    }

    // MARK: - Persistent log (JSONL)

    struct LogEntry: Encodable {
        let date: String
        let toolName: String
        let userMessage: String
        let attemptedParams: String
        let verdict: String
        let reason: String
    }

    static var logWriter: (URL, Data) throws -> Void = Self.defaultLogWriter

    static var logFileURL: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return support.appendingPathComponent("Ledger", isDirectory: true)
            .appendingPathComponent("tool-verifier.jsonl", isDirectory: false)
    }()

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func appendLog(
        toolName: String,
        rawJSON: String,
        userMessage: String,
        verdict: String,
        reason: String
    ) {
        let entry = LogEntry(
            date: isoFormatter.string(from: Date()),
            toolName: toolName,
            userMessage: userMessage,
            attemptedParams: rawJSON,
            verdict: verdict,
            reason: reason
        )

        let encoder = JSONEncoder()
        let data: Data
        do {
            let line = try encoder.encode(entry)
            data = line + Data([0x0A])
        } catch {
            logger.error("tool-verifier log encode failed: \(error.localizedDescription)")
            return
        }

        do {
            try logWriter(logFileURL, data)
        } catch {
            logger.error("tool-verifier log append failed: \(error.localizedDescription)")
        }

        switch verdict {
        case "blocked":
            logger.warning("Blocked \(toolName, privacy: .public): \(reason, privacy: .public)")
        case "flagged":
            logger.notice("Flagged \(toolName, privacy: .public): \(reason, privacy: .public)")
        default:
            break
        }
    }

    static func defaultLogWriter(_ url: URL, _ data: Data) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }

        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }

    #if DEBUG
    static func makeDefaultLogWriterForTesting() -> (URL, Data) throws -> Void {
        Self.defaultLogWriter
    }
    #endif
}

import Foundation
import SwiftData

struct SummaryKeyStats: Codable, Equatable, Sendable {
    var calories: Int
    var protein: Int
    var trained: Bool
    var hrv: String?
    var sleep: String?

    static let empty = SummaryKeyStats(
        calories: 0,
        protein: 0,
        trained: false,
        hrv: nil,
        sleep: nil
    )
}

enum PatternConfidence: String, Codable, CaseIterable, Sendable {
    case low
    case medium
    case high
}

enum LegacyLedgerSchema: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            StoredMessage.self,
            StoredMeal.self,
            StoredWorkoutSet.self,
            StoredMetric.self,
            ProfileEntry.self
        ]
    }

    @Model
    final class StoredMessage {
        var id: UUID
        var role: String
        var content: String
        var timestamp: Date

        init(id: UUID = UUID(), role: String, content: String, timestamp: Date) {
            self.id = id
            self.role = role
            self.content = content
            self.timestamp = timestamp
        }
    }

    @Model
    final class StoredMeal {
        var id: UUID
        var date: Date
        var descriptionText: String
        var calories: Int
        var protein: Int

        init(
            id: UUID = UUID(),
            date: Date,
            descriptionText: String,
            calories: Int,
            protein: Int
        ) {
            self.id = id
            self.date = date
            self.descriptionText = descriptionText
            self.calories = calories
            self.protein = protein
        }
    }

    @Model
    final class StoredWorkoutSet {
        var id: UUID
        var date: Date
        var exercise: String
        var summary: String
        var notes: String?

        init(
            id: UUID = UUID(),
            date: Date,
            exercise: String,
            summary: String,
            notes: String? = nil
        ) {
            self.id = id
            self.date = date
            self.exercise = exercise
            self.summary = summary
            self.notes = notes
        }
    }

    @Model
    final class StoredMetric {
        var id: UUID
        var date: Date
        var type: String
        var value: String
        var context: String?

        init(
            id: UUID = UUID(),
            date: Date,
            type: String,
            value: String,
            context: String? = nil
        ) {
            self.id = id
            self.date = date
            self.type = type
            self.value = value
            self.context = context
        }
    }

    @Model
    final class ProfileEntry {
        @Attribute(.unique) var key: String
        var value: String
        var updatedAt: Date

        init(key: String, value: String, updatedAt: Date = .now) {
            self.key = key
            self.value = value
            self.updatedAt = updatedAt
        }
    }
}

enum LedgerSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            StoredMessage.self,
            StoredMeal.self,
            StoredWorkoutSet.self,
            StoredMetric.self,
            IdentityProfile.self,
            Pattern.self,
            ActiveStateSnapshot.self,
            DailySummary.self,
            WeeklySummary.self,
            MonthlySummary.self,
            ProfileEntry.self
        ]
    }

    @Model
    final class StoredMessage {
        var id: UUID
        var role: String
        var content: String
        var timestamp: Date

        init(id: UUID = UUID(), role: String, content: String, timestamp: Date) {
            self.id = id
            self.role = role
            self.content = content
            self.timestamp = timestamp
        }
    }

    @Model
    final class StoredMeal {
        var id: UUID
        var date: Date
        var descriptionText: String
        var calories: Int
        var protein: Int

        init(
            id: UUID = UUID(),
            date: Date,
            descriptionText: String,
            calories: Int,
            protein: Int
        ) {
            self.id = id
            self.date = date
            self.descriptionText = descriptionText
            self.calories = calories
            self.protein = protein
        }
    }

    @Model
    final class StoredWorkoutSet {
        var id: UUID
        var date: Date
        var exercise: String
        var summary: String
        var notes: String?

        init(
            id: UUID = UUID(),
            date: Date,
            exercise: String,
            summary: String,
            notes: String? = nil
        ) {
            self.id = id
            self.date = date
            self.exercise = exercise
            self.summary = summary
            self.notes = notes
        }
    }

    @Model
    final class StoredMetric {
        var id: UUID
        var date: Date
        var type: String
        var value: String
        var context: String?

        init(
            id: UUID = UUID(),
            date: Date,
            type: String,
            value: String,
            context: String? = nil
        ) {
            self.id = id
            self.date = date
            self.type = type
            self.value = value
            self.context = context
        }
    }

    @Model
    final class IdentityProfile {
        @Attribute(.unique) var scope: String
        var markdownContent: String
        var lastUpdated: Date

        init(
            scope: String = IdentityProfile.defaultScope,
            markdownContent: String = "",
            lastUpdated: Date = .now
        ) {
            self.scope = scope
            self.markdownContent = markdownContent
            self.lastUpdated = lastUpdated
        }

        static let defaultScope = "default"
    }

    @Model
    final class Pattern {
        @Attribute(.unique) var key: String
        var descriptionText: String
        var evidenceNote: String
        var confidence: PatternConfidence
        var firstObserved: Date
        var lastReinforced: Date

        init(
            key: String,
            descriptionText: String,
            evidenceNote: String,
            confidence: PatternConfidence,
            firstObserved: Date,
            lastReinforced: Date
        ) {
            self.key = key
            self.descriptionText = descriptionText
            self.evidenceNote = evidenceNote
            self.confidence = confidence
            self.firstObserved = firstObserved
            self.lastReinforced = lastReinforced
        }
    }

    @Model
    final class ActiveStateSnapshot {
        @Attribute(.unique) var scope: String
        var markdownContent: String
        var generatedAt: Date

        init(
            scope: String = ActiveStateSnapshot.defaultScope,
            markdownContent: String,
            generatedAt: Date
        ) {
            self.scope = scope
            self.markdownContent = markdownContent
            self.generatedAt = generatedAt
        }

        static let defaultScope = "default"
    }

    @Model
    final class DailySummary {
        @Attribute(.unique) var date: Date
        var summaryText: String
        var keyStats: SummaryKeyStats
        var createdAt: Date

        init(
            date: Date,
            summaryText: String,
            keyStats: SummaryKeyStats,
            createdAt: Date = .now
        ) {
            self.date = date
            self.summaryText = summaryText
            self.keyStats = keyStats
            self.createdAt = createdAt
        }
    }

    @Model
    final class WeeklySummary {
        @Attribute(.unique) var startDate: Date
        var endDate: Date
        var summaryText: String
        var keyStats: SummaryKeyStats
        var createdAt: Date

        init(
            startDate: Date,
            endDate: Date,
            summaryText: String,
            keyStats: SummaryKeyStats,
            createdAt: Date = .now
        ) {
            self.startDate = startDate
            self.endDate = endDate
            self.summaryText = summaryText
            self.keyStats = keyStats
            self.createdAt = createdAt
        }
    }

    @Model
    final class MonthlySummary {
        @Attribute(.unique) var startDate: Date
        var endDate: Date
        var summaryText: String
        var keyStats: SummaryKeyStats
        var createdAt: Date

        init(
            startDate: Date,
            endDate: Date,
            summaryText: String,
            keyStats: SummaryKeyStats,
            createdAt: Date = .now
        ) {
            self.startDate = startDate
            self.endDate = endDate
            self.summaryText = summaryText
            self.keyStats = keyStats
            self.createdAt = createdAt
        }
    }

    @Model
    final class ProfileEntry {
        @Attribute(.unique) var key: String
        var value: String
        var updatedAt: Date

        init(key: String, value: String, updatedAt: Date = .now) {
            self.key = key
            self.value = value
            self.updatedAt = updatedAt
        }
    }
}

enum LedgerSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            StoredMessage.self,
            StoredMeal.self,
            StoredWorkoutSet.self,
            StoredMetric.self,
            IdentityProfile.self,
            Pattern.self,
            ActiveStateSnapshot.self,
            DailySummary.self,
            WeeklySummary.self,
            MonthlySummary.self
        ]
    }

    @Model
    final class StoredMessage {
        var id: UUID
        var role: String
        var content: String
        var timestamp: Date

        init(id: UUID = UUID(), role: String, content: String, timestamp: Date) {
            self.id = id
            self.role = role
            self.content = content
            self.timestamp = timestamp
        }
    }

    @Model
    final class StoredMeal {
        var id: UUID
        var date: Date
        var descriptionText: String
        var calories: Int
        var protein: Int

        init(
            id: UUID = UUID(),
            date: Date,
            descriptionText: String,
            calories: Int,
            protein: Int
        ) {
            self.id = id
            self.date = date
            self.descriptionText = descriptionText
            self.calories = calories
            self.protein = protein
        }
    }

    @Model
    final class StoredWorkoutSet {
        var id: UUID
        var date: Date
        var exercise: String
        var summary: String
        var notes: String?

        init(
            id: UUID = UUID(),
            date: Date,
            exercise: String,
            summary: String,
            notes: String? = nil
        ) {
            self.id = id
            self.date = date
            self.exercise = exercise
            self.summary = summary
            self.notes = notes
        }
    }

    @Model
    final class StoredMetric {
        var id: UUID
        var date: Date
        var type: String
        var value: String
        var context: String?

        init(
            id: UUID = UUID(),
            date: Date,
            type: String,
            value: String,
            context: String? = nil
        ) {
            self.id = id
            self.date = date
            self.type = type
            self.value = value
            self.context = context
        }
    }

    @Model
    final class IdentityProfile {
        @Attribute(.unique) var scope: String
        var markdownContent: String
        var lastUpdated: Date

        init(
            scope: String = IdentityProfile.defaultScope,
            markdownContent: String = "",
            lastUpdated: Date = .now
        ) {
            self.scope = scope
            self.markdownContent = markdownContent
            self.lastUpdated = lastUpdated
        }

        static let defaultScope = "default"
    }

    @Model
    final class Pattern {
        @Attribute(.unique) var key: String
        var descriptionText: String
        var evidenceNote: String
        var confidence: PatternConfidence
        var firstObserved: Date
        var lastReinforced: Date

        init(
            key: String,
            descriptionText: String,
            evidenceNote: String,
            confidence: PatternConfidence,
            firstObserved: Date,
            lastReinforced: Date
        ) {
            self.key = key
            self.descriptionText = descriptionText
            self.evidenceNote = evidenceNote
            self.confidence = confidence
            self.firstObserved = firstObserved
            self.lastReinforced = lastReinforced
        }
    }

    @Model
    final class ActiveStateSnapshot {
        @Attribute(.unique) var scope: String
        var markdownContent: String
        var generatedAt: Date

        init(
            scope: String = ActiveStateSnapshot.defaultScope,
            markdownContent: String,
            generatedAt: Date
        ) {
            self.scope = scope
            self.markdownContent = markdownContent
            self.generatedAt = generatedAt
        }

        static let defaultScope = "default"
    }

    @Model
    final class DailySummary {
        @Attribute(.unique) var date: Date
        var summaryText: String
        var keyStats: SummaryKeyStats
        var createdAt: Date

        init(
            date: Date,
            summaryText: String,
            keyStats: SummaryKeyStats,
            createdAt: Date = .now
        ) {
            self.date = date
            self.summaryText = summaryText
            self.keyStats = keyStats
            self.createdAt = createdAt
        }
    }

    @Model
    final class WeeklySummary {
        @Attribute(.unique) var startDate: Date
        var endDate: Date
        var summaryText: String
        var keyStats: SummaryKeyStats
        var createdAt: Date

        init(
            startDate: Date,
            endDate: Date,
            summaryText: String,
            keyStats: SummaryKeyStats,
            createdAt: Date = .now
        ) {
            self.startDate = startDate
            self.endDate = endDate
            self.summaryText = summaryText
            self.keyStats = keyStats
            self.createdAt = createdAt
        }
    }

    @Model
    final class MonthlySummary {
        @Attribute(.unique) var startDate: Date
        var endDate: Date
        var summaryText: String
        var keyStats: SummaryKeyStats
        var createdAt: Date

        init(
            startDate: Date,
            endDate: Date,
            summaryText: String,
            keyStats: SummaryKeyStats,
            createdAt: Date = .now
        ) {
            self.startDate = startDate
            self.endDate = endDate
            self.summaryText = summaryText
            self.keyStats = keyStats
            self.createdAt = createdAt
        }
    }
}

typealias StoredMessage = LedgerSchemaV2.StoredMessage
typealias StoredMeal = LedgerSchemaV2.StoredMeal
typealias StoredWorkoutSet = LedgerSchemaV2.StoredWorkoutSet
typealias StoredMetric = LedgerSchemaV2.StoredMetric
typealias IdentityProfile = LedgerSchemaV2.IdentityProfile
typealias Pattern = LedgerSchemaV2.Pattern
typealias ActiveStateSnapshot = LedgerSchemaV2.ActiveStateSnapshot
typealias DailySummary = LedgerSchemaV2.DailySummary
typealias WeeklySummary = LedgerSchemaV2.WeeklySummary
typealias MonthlySummary = LedgerSchemaV2.MonthlySummary

enum IdentityProfileSection: String, CaseIterable, Sendable {
    case goals = "Goals"
    case body = "Body"
    case constraints = "Constraints"
    case preferences = "Preferences"
    case lifestyle = "Lifestyle"
    case other = "Other"
}

enum IdentityProfileDocument {
    static func upserting(
        key: String,
        value: String,
        into markdown: String
    ) -> String {
        var sections = parse(markdown)
        let normalizedKey = normalizeKey(key)
        let normalizedValue = normalizeValue(value)

        guard !normalizedKey.isEmpty, !normalizedValue.isEmpty else {
            return render(sections)
        }

        for section in IdentityProfileSection.allCases {
            sections[section]?.removeValue(forKey: normalizedKey)
        }
        sections[section(forKey: normalizedKey), default: [:]][normalizedKey] = normalizedValue
        return render(sections)
    }

    static func merging(
        markdown: String,
        with updates: [(key: String, value: String)]
    ) -> String {
        updates.reduce(markdown) { partialResult, update in
            upserting(key: update.key, value: update.value, into: partialResult)
        }
    }

    static func facts(from markdown: String) -> [String: String] {
        parse(markdown)
            .values
            .reduce(into: [String: String]()) { result, sectionFacts in
                result.merge(sectionFacts, uniquingKeysWith: { _, latest in latest })
            }
    }

    static func sections(from markdown: String) -> [String: [String: String]] {
        parse(markdown).reduce(into: [String: [String: String]]()) { result, entry in
            result[entry.key.rawValue] = entry.value
        }
    }

    static func render(_ sections: [IdentityProfileSection: [String: String]]) -> String {
        IdentityProfileSection.allCases
            .compactMap { section -> String? in
                guard
                    let facts = sections[section],
                    !facts.isEmpty
                else {
                    return nil
                }

                let lines = facts.keys.sorted().map { key in
                    "- \(key): \(facts[key] ?? "")"
                }
                return "## \(section.rawValue)\n" + lines.joined(separator: "\n")
            }
            .joined(separator: "\n\n")
    }

    static func section(forKey key: String) -> IdentityProfileSection {
        let normalizedKey = normalizeKey(key)
        let bodyTokens = ["age", "height", "weight", "bodyfat", "body_fat", "sex"]
        let goalTokens = ["goal", "target", "cut", "bulk", "maintain", "recomp"]
        let constraintTokens = ["constraint", "injury", "pain", "allergy", "intolerance", "restriction", "limit"]
        let preferenceTokens = ["prefer", "preference", "favorite", "diet", "training_time", "meal", "food", "split"]
        let lifestyleTokens = ["lifestyle", "work", "job", "travel", "social", "family", "schedule", "routine", "sleeping"]

        if containsAnyToken(in: normalizedKey, tokens: goalTokens) {
            return .goals
        }
        if containsAnyToken(in: normalizedKey, tokens: bodyTokens) {
            return .body
        }
        if containsAnyToken(in: normalizedKey, tokens: constraintTokens) {
            return .constraints
        }
        if containsAnyToken(in: normalizedKey, tokens: preferenceTokens) {
            return .preferences
        }
        if containsAnyToken(in: normalizedKey, tokens: lifestyleTokens) {
            return .lifestyle
        }
        return .other
    }

    private static func parse(_ markdown: String) -> [IdentityProfileSection: [String: String]] {
        var sections = IdentityProfileSection.allCases.reduce(into: [IdentityProfileSection: [String: String]]()) {
            $0[$1] = [:]
        }
        var currentSection: IdentityProfileSection?

        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)

            if line.hasPrefix("## ") {
                let title = String(line.dropFirst(3))
                currentSection = IdentityProfileSection.allCases.first(where: { $0.rawValue == title })
                continue
            }

            guard
                line.hasPrefix("- "),
                let currentSection,
                let colonIndex = line.firstIndex(of: ":")
            else {
                continue
            }

            let keyPart = line[line.index(line.startIndex, offsetBy: 2) ..< colonIndex]
            let valuePart = line[line.index(after: colonIndex)...]
            let key = normalizeKey(String(keyPart))
            let value = normalizeValue(String(valuePart))

            guard !key.isEmpty, !value.isEmpty else {
                continue
            }

            sections[currentSection, default: [:]][key] = value
        }

        return sections
    }

    private static func containsAnyToken(in value: String, tokens: [String]) -> Bool {
        tokens.contains { token in
            value.contains(token)
        }
    }

    private static func normalizeKey(_ key: String) -> String {
        key
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
    }

    private static func normalizeValue(_ value: String) -> String {
        value
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

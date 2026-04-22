import Foundation
import SwiftData

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

import Foundation
import SwiftData

enum LedgerPersistentModels {
    static let schema = Schema([
        StoredMessage.self,
        StoredMeal.self,
        StoredWorkoutSet.self,
        StoredMetric.self,
        ProfileEntry.self
    ])

    static func makeContainer(
        url: URL? = nil,
        inMemory: Bool = false
    ) throws -> ModelContainer {
        let configuration: ModelConfiguration
        if let url {
            configuration = ModelConfiguration(url: url)
        } else {
            configuration = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        }

        return try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
    }
}

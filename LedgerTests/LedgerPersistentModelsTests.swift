import SwiftData
import XCTest
@testable import Ledger

final class LedgerPersistentModelsTests: XCTestCase {
    func testMigratesLegacyProfileEntriesIntoIdentityProfile() throws {
        let storeURL = try TestHelpers.makeTemporaryStoreURL(testName: #function)

        do {
            let legacyContainer = try LedgerPersistentModels.makeV1Container(url: storeURL)
            let legacyContext = ModelContext(legacyContainer)
            legacyContext.insert(
                LedgerSchemaV1.ProfileEntry(
                    key: "goal_weight",
                    value: "78kg"
                )
            )
            legacyContext.insert(
                LedgerSchemaV1.ProfileEntry(
                    key: "training_time",
                    value: "evenings"
                )
            )
            try legacyContext.save()
        }

        let migratedContainer = try LedgerPersistentModels.makeContainer(url: storeURL)
        let migratedContext = ModelContext(migratedContainer)
        let profiles = try migratedContext.fetch(FetchDescriptor<IdentityProfile>())

        XCTAssertEqual(profiles.count, 1)
        XCTAssertEqual(profiles.first?.scope, IdentityProfile.defaultScope)
        XCTAssertTrue(profiles.first?.markdownContent.contains("## Goals") == true)
        XCTAssertTrue(profiles.first?.markdownContent.contains("- goal_weight: 78kg") == true)
        XCTAssertTrue(profiles.first?.markdownContent.contains("## Preferences") == true)
        XCTAssertTrue(profiles.first?.markdownContent.contains("- training_time: evenings") == true)
        XCTAssertFalse(LedgerPersistentModels.currentSchema.entitiesByName.keys.contains("ProfileEntry"))
    }
}

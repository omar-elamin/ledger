import Foundation
import SwiftData

enum LedgerPersistentModels {
    static let currentSchema = Schema(versionedSchema: LedgerSchemaV2.self)
    static let v1Schema = Schema(versionedSchema: LedgerSchemaV1.self)

    static func makeContainer(
        url: URL? = nil,
        inMemory: Bool = false
    ) throws -> ModelContainer {
        let configuration = makeConfiguration(url: url, inMemory: inMemory)
        return try ModelContainer(
            for: currentSchema,
            migrationPlan: LedgerSchemaMigrationPlan.self,
            configurations: [configuration]
        )
    }

    static func makeV1Container(
        url: URL? = nil,
        inMemory: Bool = false
    ) throws -> ModelContainer {
        let configuration = makeConfiguration(url: url, inMemory: inMemory)
        return try ModelContainer(
            for: v1Schema,
            configurations: [configuration]
        )
    }

    private static func makeConfiguration(url: URL?, inMemory: Bool) -> ModelConfiguration {
        if let url {
            return ModelConfiguration(url: url)
        }
        return ModelConfiguration(isStoredInMemoryOnly: inMemory)
    }
}

enum LedgerSchemaMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [
            LedgerSchemaV1.self,
            LedgerSchemaV2.self
        ]
    }

    static var stages: [MigrationStage] {
        [
            .custom(
                fromVersion: LedgerSchemaV1.self,
                toVersion: LedgerSchemaV2.self,
                willMigrate: { context in
                    try migrateLegacyProfileEntries(in: context)
                },
                didMigrate: nil
            )
        ]
    }

    private static func migrateLegacyProfileEntries(in context: ModelContext) throws {
        let entries = try context.fetch(
            FetchDescriptor<LedgerSchemaV1.ProfileEntry>(
                sortBy: [SortDescriptor(\.updatedAt, order: .forward)]
            )
        )

        guard !entries.isEmpty else {
            return
        }

        var descriptor = FetchDescriptor<LedgerSchemaV1.IdentityProfile>(
            predicate: #Predicate { profile in
                profile.scope == "default"
            }
        )
        descriptor.fetchLimit = 1

        let existingProfile = try context.fetch(descriptor).first
        let mergedMarkdown = IdentityProfileDocument.merging(
            markdown: existingProfile?.markdownContent ?? "",
            with: entries.map { (key: $0.key, value: $0.value) }
        )
        let lastUpdated = entries.map(\.updatedAt).max() ?? existingProfile?.lastUpdated ?? .now

        if let existingProfile {
            existingProfile.markdownContent = mergedMarkdown
            existingProfile.lastUpdated = max(existingProfile.lastUpdated, lastUpdated)
        } else {
            context.insert(
                LedgerSchemaV1.IdentityProfile(
                    scope: "default",
                    markdownContent: mergedMarkdown,
                    lastUpdated: lastUpdated
                )
            )
        }

        for entry in entries {
            context.delete(entry)
        }

        try context.save()
    }
}

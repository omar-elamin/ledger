import Foundation
import SQLite3
import SwiftData

enum LedgerPersistentModels {
    static let legacySchema = Schema(versionedSchema: LegacyLedgerSchema.self)
    static let currentSchema = Schema(versionedSchema: LedgerSchemaV2.self)
    static let v1Schema = Schema(versionedSchema: LedgerSchemaV1.self)

    static func makeContainer(
        url: URL? = nil,
        inMemory: Bool = false
    ) throws -> ModelContainer {
        let resolvedURL = resolvedStoreURL(url: url, inMemory: inMemory)
        let configuration = makeConfiguration(url: resolvedURL, inMemory: inMemory)

        if
            !inMemory,
            let resolvedURL,
            looksLikeLegacyStore(at: resolvedURL)
        {
            _ = try recoverLegacyStoreIfNeeded(at: resolvedURL)
            return try ModelContainer(
                for: currentSchema,
                migrationPlan: LedgerSchemaMigrationPlan.self,
                configurations: [configuration]
            )
        }

        do {
            return try ModelContainer(
                for: currentSchema,
                migrationPlan: LedgerSchemaMigrationPlan.self,
                configurations: [configuration]
            )
        } catch {
            guard
                !inMemory,
                let resolvedURL,
                try recoverLegacyStoreIfNeeded(at: resolvedURL)
            else {
                throw error
            }

            return try ModelContainer(
                for: currentSchema,
                migrationPlan: LedgerSchemaMigrationPlan.self,
                configurations: [configuration]
            )
        }
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

    static func makeLegacyContainer(
        url: URL? = nil,
        inMemory: Bool = false
    ) throws -> ModelContainer {
        let configuration = makeConfiguration(url: resolvedStoreURL(url: url, inMemory: inMemory), inMemory: inMemory)
        return try ModelContainer(
            for: legacySchema,
            configurations: [configuration]
        )
    }

    private static func makeConfiguration(url: URL?, inMemory: Bool) -> ModelConfiguration {
        if let url {
            return ModelConfiguration(url: url)
        }
        return ModelConfiguration(isStoredInMemoryOnly: inMemory)
    }

    private static func resolvedStoreURL(url: URL?, inMemory: Bool) -> URL? {
        if inMemory {
            return nil
        }

        if let url {
            return url
        }

        let applicationSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first

        return applicationSupportURL?.appendingPathComponent("default.store")
    }

    private static func recoverLegacyStoreIfNeeded(at storeURL: URL) throws -> Bool {
        guard FileManager.default.fileExists(atPath: storeURL.path) else {
            return false
        }

        guard let snapshot = try captureLegacySnapshot(at: storeURL) else {
            return false
        }

        let backupURLs = try backupStoreFiles(at: storeURL)
        do {
            let recoveredContainer = try makeContainerWithoutRecovery(url: storeURL)
            try importLegacySnapshot(snapshot, into: recoveredContainer)
            print("Recovered legacy Ledger store from \(backupURLs.store.lastPathComponent).")
            return true
        } catch {
            try restoreBackedUpStoreFiles(from: backupURLs, to: storeURL)
            throw error
        }
    }

    private static func makeContainerWithoutRecovery(url: URL) throws -> ModelContainer {
        let configuration = makeConfiguration(url: url, inMemory: false)
        return try ModelContainer(
            for: currentSchema,
            migrationPlan: LedgerSchemaMigrationPlan.self,
            configurations: [configuration]
        )
    }

    private static func captureLegacySnapshot(at storeURL: URL) throws -> LegacyStoreSnapshot? {
        let legacyContainer: ModelContainer
        do {
            legacyContainer = try makeLegacyContainer(url: storeURL)
        } catch {
            return nil
        }

        let context = ModelContext(legacyContainer)
        let messages = try context.fetch(
            FetchDescriptor<LegacyLedgerSchema.StoredMessage>(
                sortBy: [SortDescriptor(\.timestamp, order: .forward)]
            )
        )
        let meals = try context.fetch(
            FetchDescriptor<LegacyLedgerSchema.StoredMeal>(
                sortBy: [SortDescriptor(\.date, order: .forward)]
            )
        )
        let workouts = try context.fetch(
            FetchDescriptor<LegacyLedgerSchema.StoredWorkoutSet>(
                sortBy: [SortDescriptor(\.date, order: .forward)]
            )
        )
        let metrics = try context.fetch(
            FetchDescriptor<LegacyLedgerSchema.StoredMetric>(
                sortBy: [SortDescriptor(\.date, order: .forward)]
            )
        )
        let profileEntries = try context.fetch(
            FetchDescriptor<LegacyLedgerSchema.ProfileEntry>(
                sortBy: [SortDescriptor(\.updatedAt, order: .forward)]
            )
        )

        return LegacyStoreSnapshot(
            messages: messages.map {
                LegacyMessageValue(id: $0.id, role: $0.role, content: $0.content, timestamp: $0.timestamp)
            },
            meals: meals.map {
                LegacyMealValue(
                    id: $0.id,
                    date: $0.date,
                    descriptionText: $0.descriptionText,
                    calories: $0.calories,
                    protein: $0.protein
                )
            },
            workouts: workouts.map {
                LegacyWorkoutValue(
                    id: $0.id,
                    date: $0.date,
                    exercise: $0.exercise,
                    summary: $0.summary,
                    notes: $0.notes
                )
            },
            metrics: metrics.map {
                LegacyMetricValue(
                    id: $0.id,
                    date: $0.date,
                    type: $0.type,
                    value: $0.value,
                    context: $0.context
                )
            },
            profileEntries: profileEntries.map {
                LegacyProfileEntryValue(key: $0.key, value: $0.value, updatedAt: $0.updatedAt)
            }
        )
    }

    private static func importLegacySnapshot(_ snapshot: LegacyStoreSnapshot, into container: ModelContainer) throws {
        let context = ModelContext(container)

        snapshot.messages.forEach {
            context.insert(
                StoredMessage(
                    id: $0.id,
                    role: $0.role,
                    content: $0.content,
                    timestamp: $0.timestamp
                )
            )
        }
        snapshot.meals.forEach {
            context.insert(
                StoredMeal(
                    id: $0.id,
                    date: $0.date,
                    descriptionText: $0.descriptionText,
                    calories: $0.calories,
                    protein: $0.protein
                )
            )
        }
        snapshot.workouts.forEach {
            context.insert(
                StoredWorkoutSet(
                    id: $0.id,
                    date: $0.date,
                    exercise: $0.exercise,
                    summary: $0.summary,
                    notes: $0.notes
                )
            )
        }
        snapshot.metrics.forEach {
            context.insert(
                StoredMetric(
                    id: $0.id,
                    date: $0.date,
                    type: $0.type,
                    value: $0.value,
                    context: $0.context
                )
            )
        }

        if !snapshot.profileEntries.isEmpty {
            let markdown = IdentityProfileDocument.merging(
                markdown: "",
                with: snapshot.profileEntries.map { (key: $0.key, value: $0.value) }
            )
            let lastUpdated = snapshot.profileEntries.map(\.updatedAt).max() ?? .now
            context.insert(
                IdentityProfile(
                    scope: IdentityProfile.defaultScope,
                    markdownContent: markdown,
                    lastUpdated: lastUpdated
                )
            )
        }

        try context.save()
    }

    private static func backupStoreFiles(at storeURL: URL) throws -> BackedUpStoreURLs {
        let fileManager = FileManager.default
        let storeBackupURL = backupURL(for: storeURL)
        let walURL = sidecarURL(for: storeURL, suffix: "-wal")
        let shmURL = sidecarURL(for: storeURL, suffix: "-shm")
        let walBackupURL = backupURL(for: walURL)
        let shmBackupURL = backupURL(for: shmURL)

        [storeBackupURL, walBackupURL, shmBackupURL].forEach { backupURL in
            try? fileManager.removeItem(at: backupURL)
        }

        try fileManager.moveItem(at: storeURL, to: storeBackupURL)
        if fileManager.fileExists(atPath: walURL.path) {
            try fileManager.moveItem(at: walURL, to: walBackupURL)
        }
        if fileManager.fileExists(atPath: shmURL.path) {
            try fileManager.moveItem(at: shmURL, to: shmBackupURL)
        }

        return BackedUpStoreURLs(
            store: storeBackupURL,
            wal: fileManager.fileExists(atPath: walBackupURL.path) ? walBackupURL : nil,
            shm: fileManager.fileExists(atPath: shmBackupURL.path) ? shmBackupURL : nil
        )
    }

    private static func restoreBackedUpStoreFiles(from backups: BackedUpStoreURLs, to storeURL: URL) throws {
        let fileManager = FileManager.default
        try? removeStoreFiles(at: storeURL)

        if fileManager.fileExists(atPath: backups.store.path) {
            try fileManager.moveItem(at: backups.store, to: storeURL)
        }
        if let walBackupURL = backups.wal, fileManager.fileExists(atPath: walBackupURL.path) {
            try fileManager.moveItem(at: walBackupURL, to: sidecarURL(for: storeURL, suffix: "-wal"))
        }
        if let shmBackupURL = backups.shm, fileManager.fileExists(atPath: shmBackupURL.path) {
            try fileManager.moveItem(at: shmBackupURL, to: sidecarURL(for: storeURL, suffix: "-shm"))
        }
    }

    private static func removeStoreFiles(at storeURL: URL) throws {
        let fileManager = FileManager.default
        [storeURL, sidecarURL(for: storeURL, suffix: "-wal"), sidecarURL(for: storeURL, suffix: "-shm")]
            .forEach { url in
                if fileManager.fileExists(atPath: url.path) {
                    try? fileManager.removeItem(at: url)
                }
            }
    }

    private static func sidecarURL(for storeURL: URL, suffix: String) -> URL {
        URL(fileURLWithPath: storeURL.path + suffix)
    }

    private static func backupURL(for url: URL) -> URL {
        URL(fileURLWithPath: url.path + ".legacy-backup")
    }

    private static func looksLikeLegacyStore(at storeURL: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: storeURL.path) else {
            return false
        }

        var database: OpaquePointer?
        guard sqlite3_open_v2(storeURL.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            if let database {
                sqlite3_close(database)
            }
            return false
        }
        defer { sqlite3_close(database) }

        let query = "SELECT name FROM sqlite_master WHERE type = 'table';"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK else {
            if let statement {
                sqlite3_finalize(statement)
            }
            return false
        }
        defer { sqlite3_finalize(statement) }

        var tableNames = Set<String>()
        while sqlite3_step(statement) == SQLITE_ROW {
            if let cString = sqlite3_column_text(statement, 0) {
                tableNames.insert(String(cString: cString))
            }
        }

        let currentOnlyTables: Set<String> = [
            "ZIDENTITYPROFILE",
            "ZPATTERN",
            "ZACTIVESTATESNAPSHOT",
            "ZDAILYSUMMARY",
            "ZWEEKLYSUMMARY",
            "ZMONTHLYSUMMARY"
        ]

        return tableNames.contains("ZPROFILEENTRY") && currentOnlyTables.isDisjoint(with: tableNames)
    }
}

private struct LegacyStoreSnapshot {
    let messages: [LegacyMessageValue]
    let meals: [LegacyMealValue]
    let workouts: [LegacyWorkoutValue]
    let metrics: [LegacyMetricValue]
    let profileEntries: [LegacyProfileEntryValue]
}

private struct LegacyMessageValue {
    let id: UUID
    let role: String
    let content: String
    let timestamp: Date
}

private struct LegacyMealValue {
    let id: UUID
    let date: Date
    let descriptionText: String
    let calories: Int
    let protein: Int
}

private struct LegacyWorkoutValue {
    let id: UUID
    let date: Date
    let exercise: String
    let summary: String
    let notes: String?
}

private struct LegacyMetricValue {
    let id: UUID
    let date: Date
    let type: String
    let value: String
    let context: String?
}

private struct LegacyProfileEntryValue {
    let key: String
    let value: String
    let updatedAt: Date
}

private struct BackedUpStoreURLs {
    let store: URL
    let wal: URL?
    let shm: URL?
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

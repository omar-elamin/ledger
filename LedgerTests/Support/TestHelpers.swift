import Foundation
import SwiftData
import XCTest
@testable import Ledger

enum TestHelpers {
    static func makeInMemoryContainer() throws -> ModelContainer {
        try LedgerPersistentModels.makeContainer(inMemory: true)
    }

    static func fetchAll<T: PersistentModel>(
        _ type: T.Type,
        from context: ModelContext
    ) throws -> [T] {
        try context.fetch(FetchDescriptor<T>())
    }

    static func fetchMessages(from context: ModelContext) throws -> [StoredMessage] {
        try context.fetch(
            FetchDescriptor<StoredMessage>(
                sortBy: [SortDescriptor(\.timestamp, order: .forward)]
            )
        )
    }
}

extension XCTestCase {
    @MainActor
    func waitUntil(
        timeout: TimeInterval = 2,
        pollIntervalNanoseconds: UInt64 = 20_000_000,
        condition: @escaping @MainActor () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        }
        XCTAssertTrue(condition())
    }
}

struct TestError: Error {}

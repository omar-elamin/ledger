import Foundation
import SwiftData
import SwiftUI
import XCTest
@testable import Ledger

@MainActor
final class MemoryMaintenanceSchedulerTests: XCTestCase {
    func testNextScheduledRunUsesSameDayBeforeWindowAndNextDayAfterWindow() throws {
        let calendar = makeCalendar()
        let now = makeDate(year: 2026, month: 4, day: 22, hour: 1, minute: 5, calendar: calendar)
        let scheduler = makeScheduler(
            now: now,
            calendar: calendar,
            backgroundTaskScheduler: RecordingBackgroundTaskScheduler()
        )

        let sameDayRun = scheduler.nextScheduledRun(after: now)
        XCTAssertEqual(
            sameDayRun,
            makeDate(year: 2026, month: 4, day: 22, hour: 3, minute: 15, calendar: calendar)
        )

        let afterWindow = makeDate(year: 2026, month: 4, day: 22, hour: 4, minute: 0, calendar: calendar)
        let nextDayRun = scheduler.nextScheduledRun(after: afterWindow)
        XCTAssertEqual(
            nextDayRun,
            makeDate(year: 2026, month: 4, day: 23, hour: 3, minute: 15, calendar: calendar)
        )
    }

    func testRegisterBackgroundTasksRegistersAndSchedulesChargingRequest() throws {
        let calendar = makeCalendar()
        let now = makeDate(year: 2026, month: 4, day: 22, hour: 1, minute: 5, calendar: calendar)
        let backgroundScheduler = RecordingBackgroundTaskScheduler()
        let scheduler = makeScheduler(
            now: now,
            calendar: calendar,
            backgroundTaskScheduler: backgroundScheduler
        )

        scheduler.registerBackgroundTasks()
        scheduler.registerBackgroundTasks()

        XCTAssertEqual(backgroundScheduler.registeredIdentifiers, [MemoryMaintenanceScheduler.taskIdentifier])
        XCTAssertEqual(backgroundScheduler.submittedRequests.count, 1)

        let request = try XCTUnwrap(backgroundScheduler.submittedRequests.first)
        XCTAssertEqual(request.identifier, MemoryMaintenanceScheduler.taskIdentifier)
        XCTAssertEqual(request.earliestBeginDate, makeDate(year: 2026, month: 4, day: 22, hour: 3, minute: 15, calendar: calendar))
        XCTAssertTrue(request.requiresExternalPower)
        XCTAssertTrue(request.requiresNetworkConnectivity)
    }

    func testHandleScenePhaseChangeRunsForegroundCatchupWhenNightlyIsStale() async throws {
        let calendar = makeCalendar()
        let now = makeDate(year: 2026, month: 4, day: 22, hour: 9, minute: 30, calendar: calendar)
        let backgroundScheduler = RecordingBackgroundTaskScheduler()
        let isolatedDefaults = makeIsolatedUserDefaults()
        let userDefaults = isolatedDefaults.userDefaults
        defer { clear(isolatedDefaults) }
        userDefaults.set(now, forKey: MemoryMaintenanceCoordinator.weeklyRunKey)

        let container = try TestHelpers.makeInMemoryContainer()
        let generator = SchedulerStubMemoryTextGenerator(
            responses: [
                "### Snapshot\n- Weight: missing",
                "Quiet day with no structured logs yet."
            ]
        )
        let maintainer = MemoryMaintainer(
            modelContainer: container,
            textGenerator: generator,
            calendar: calendar,
            now: { now }
        )
        let coordinator = MemoryMaintenanceCoordinator(
            maintainer: maintainer,
            textGenerator: generator,
            userDefaults: userDefaults,
            calendar: calendar,
            now: { now }
        )
        let scheduler = MemoryMaintenanceScheduler(
            coordinator: coordinator,
            backgroundTaskScheduler: backgroundScheduler,
            calendar: calendar,
            now: { now }
        )

        scheduler.handleScenePhaseChange(.active)

        await waitUntil {
            (userDefaults.object(forKey: MemoryMaintenanceCoordinator.nightlyRunKey) as? Date) != nil
        }

        let context = ModelContext(container)
        XCTAssertEqual(backgroundScheduler.submittedRequests.count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ActiveStateSnapshot>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<DailySummary>()).count, 1)
        XCTAssertEqual(
            userDefaults.object(forKey: MemoryMaintenanceCoordinator.weeklyRunKey) as? Date,
            now
        )
    }

    func testCoordinatorUsesNightlyAndWeeklyGatesFromStoredTimestamps() async throws {
        let calendar = makeCalendar()
        let now = makeDate(year: 2026, month: 4, day: 22, hour: 9, minute: 30, calendar: calendar)
        let isolatedDefaults = makeIsolatedUserDefaults()
        let userDefaults = isolatedDefaults.userDefaults
        defer { clear(isolatedDefaults) }

        let container = try TestHelpers.makeInMemoryContainer()
        let generator = SchedulerStubMemoryTextGenerator(responses: [])
        let coordinator = MemoryMaintenanceCoordinator(
            maintainer: MemoryMaintainer(
                modelContainer: container,
                textGenerator: generator,
                calendar: calendar,
                now: { now }
            ),
            textGenerator: generator,
            userDefaults: userDefaults,
            calendar: calendar,
            now: { now }
        )

        let initialNightly = await coordinator.shouldRunNightly(at: now)
        let initialWeekly = await coordinator.shouldRunWeekly(at: now)
        XCTAssertTrue(initialNightly)
        XCTAssertTrue(initialWeekly)

        userDefaults.set(now.addingTimeInterval(-12 * 60 * 60), forKey: MemoryMaintenanceCoordinator.nightlyRunKey)
        let recentNightly = await coordinator.shouldRunNightly(at: now)
        XCTAssertFalse(recentNightly)

        userDefaults.set(now.addingTimeInterval(-(37 * 60 * 60)), forKey: MemoryMaintenanceCoordinator.nightlyRunKey)
        let staleNightly = await coordinator.shouldRunNightly(at: now)
        XCTAssertTrue(staleNightly)

        userDefaults.set(now.addingTimeInterval(-(6 * 24 * 60 * 60)), forKey: MemoryMaintenanceCoordinator.weeklyRunKey)
        let recentWeekly = await coordinator.shouldRunWeekly(at: now)
        XCTAssertFalse(recentWeekly)

        userDefaults.set(now.addingTimeInterval(-(8 * 24 * 60 * 60)), forKey: MemoryMaintenanceCoordinator.weeklyRunKey)
        let staleWeekly = await coordinator.shouldRunWeekly(at: now)
        XCTAssertTrue(staleWeekly)

        let sunday = makeDate(year: 2026, month: 4, day: 26, hour: 9, minute: 30, calendar: calendar)
        userDefaults.set(sunday.addingTimeInterval(-(24 * 60 * 60)), forKey: MemoryMaintenanceCoordinator.weeklyRunKey)
        let sundayWeekly = await coordinator.shouldRunWeekly(at: sunday)
        XCTAssertTrue(sundayWeekly)
    }

    func testBackgroundTaskExpirationCancelsWorkAndReschedules() async throws {
        let calendar = makeCalendar()
        let now = makeDate(year: 2026, month: 4, day: 22, hour: 9, minute: 30, calendar: calendar)
        let backgroundScheduler = RecordingBackgroundTaskScheduler()
        let isolatedDefaults = makeIsolatedUserDefaults()
        let userDefaults = isolatedDefaults.userDefaults
        defer { clear(isolatedDefaults) }

        let container = try TestHelpers.makeInMemoryContainer()
        let generator = SchedulerStubMemoryTextGenerator(
            responses: ["### Snapshot\n- Weight: missing"],
            delayNanoseconds: 5_000_000_000
        )
        let maintainer = MemoryMaintainer(
            modelContainer: container,
            textGenerator: generator,
            calendar: calendar,
            now: { now }
        )
        let coordinator = MemoryMaintenanceCoordinator(
            maintainer: maintainer,
            textGenerator: generator,
            userDefaults: userDefaults,
            calendar: calendar,
            now: { now }
        )
        let scheduler = MemoryMaintenanceScheduler(
            coordinator: coordinator,
            backgroundTaskScheduler: backgroundScheduler,
            calendar: calendar,
            now: { now }
        )

        scheduler.registerBackgroundTasks()

        let launchHandler = try XCTUnwrap(backgroundScheduler.launchHandler)
        let task = RecordingBackgroundProcessingTask()
        launchHandler(task)

        XCTAssertEqual(backgroundScheduler.submittedRequests.count, 2)
        XCTAssertNotNil(task.expirationHandler)

        task.expirationHandler?()
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(backgroundScheduler.submittedRequests.count, 3)
        XCTAssertTrue(task.completions.isEmpty)
        XCTAssertNil(userDefaults.object(forKey: MemoryMaintenanceCoordinator.nightlyRunKey) as? Date)
    }

    private func makeScheduler(
        now: Date,
        calendar: Calendar,
        backgroundTaskScheduler: RecordingBackgroundTaskScheduler
    ) -> MemoryMaintenanceScheduler {
        let container = try! TestHelpers.makeInMemoryContainer()
        let generator = SchedulerStubMemoryTextGenerator(responses: [])
        let coordinator = MemoryMaintenanceCoordinator(
            maintainer: MemoryMaintainer(
                modelContainer: container,
                textGenerator: generator,
                calendar: calendar,
                now: { now }
            ),
            textGenerator: generator,
            userDefaults: makeIsolatedUserDefaults().userDefaults,
            calendar: calendar,
            now: { now }
        )
        return MemoryMaintenanceScheduler(
            coordinator: coordinator,
            backgroundTaskScheduler: backgroundTaskScheduler,
            calendar: calendar,
            now: { now }
        )
    }

    private func makeCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }

    private func makeDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int,
        calendar: Calendar
    ) -> Date {
        calendar.date(
            from: DateComponents(
                calendar: calendar,
                timeZone: calendar.timeZone,
                year: year,
                month: month,
                day: day,
                hour: hour,
                minute: minute
            )
        )!
    }

    private func makeIsolatedUserDefaults() -> IsolatedUserDefaults {
        let suiteName = "MemoryMaintenanceSchedulerTests.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        let isolated = IsolatedUserDefaults(suiteName: suiteName, userDefaults: userDefaults)
        clear(isolated)
        return isolated
    }

    private func clear(_ isolatedUserDefaults: IsolatedUserDefaults) {
        isolatedUserDefaults.userDefaults.removePersistentDomain(forName: isolatedUserDefaults.suiteName)
    }
}

private struct IsolatedUserDefaults {
    let suiteName: String
    let userDefaults: UserDefaults
}

private final class RecordingBackgroundTaskScheduler: BackgroundTaskScheduling {
    private(set) var registeredIdentifiers: [String] = []
    private(set) var submittedRequests: [BackgroundProcessingRequest] = []
    var launchHandler: ((BackgroundProcessingTaskHandling) -> Void)?

    func register(
        identifier: String,
        launchHandler: @escaping (BackgroundProcessingTaskHandling) -> Void
    ) -> Bool {
        registeredIdentifiers.append(identifier)
        self.launchHandler = launchHandler
        return true
    }

    func submit(_ request: BackgroundProcessingRequest) throws {
        submittedRequests.append(request)
    }
}

private final class RecordingBackgroundProcessingTask: BackgroundProcessingTaskHandling {
    var expirationHandler: (() -> Void)?
    private(set) var completions: [Bool] = []

    func setTaskCompleted(success: Bool) {
        completions.append(success)
    }
}

private actor SchedulerStubMemoryTextGenerator: MemoryTextGeneratingClient {
    nonisolated let hasAPIKeyConfigured = true

    private var responses: [String]
    private let delayNanoseconds: UInt64?

    init(
        responses: [String],
        delayNanoseconds: UInt64? = nil
    ) {
        self.responses = responses
        self.delayNanoseconds = delayNanoseconds
    }

    func generateText(
        systemPrompt: String,
        userPrompt: String,
        maxTokens: Int
    ) async throws -> String {
        if let delayNanoseconds {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }

        if responses.isEmpty {
            return "Stub response."
        }

        return responses.removeFirst()
    }
}

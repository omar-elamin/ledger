import BackgroundTasks
import Foundation
import OSLog
import SwiftUI

actor MemoryMaintenanceCoordinator {
    static let nightlyRunKey = "ledger.memory.lastSuccessfulNightlyRunAt"
    static let weeklyRunKey = "ledger.memory.lastSuccessfulWeeklyMaintenanceAt"

    private let maintainer: MemoryMaintainer
    private let textGenerator: any MemoryTextGeneratingClient
    private let userDefaults: UserDefaults
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    private let logger = Logger(subsystem: "com.omarelamin.ledger", category: "MemoryCoordinator")
    private var isRunning = false

    init(
        maintainer: MemoryMaintainer,
        textGenerator: any MemoryTextGeneratingClient,
        userDefaults: UserDefaults = .standard,
        calendar: Calendar = .autoupdatingCurrent,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.maintainer = maintainer
        self.textGenerator = textGenerator
        self.userDefaults = userDefaults
        self.calendar = calendar
        self.now = now
    }

    func runNightlySequence(force: Bool, trigger: String) async -> Bool {
        if isRunning {
            logger.debug("Skipping \(trigger, privacy: .public) memory run because one is already in flight.")
            return false
        }

        if !force, !shouldRunNightly(at: now()) {
            return true
        }

        guard textGenerator.hasAPIKeyConfigured else {
            logger.info("Skipping memory maintenance because no API key is configured.")
            return true
        }

        isRunning = true
        defer { isRunning = false }

        let runDate = now()

        do {
            try Task.checkCancellation()
            try await maintainer.updateActiveState()

            try Task.checkCancellation()
            try await maintainer.summarizeToday()

            if shouldRunWeekly(at: runDate) {
                try Task.checkCancellation()
                try await maintainer.updatePatterns()

                try Task.checkCancellation()
                try await maintainer.proposeIdentityUpdates()

                userDefaults.set(runDate, forKey: Self.weeklyRunKey)
            }

            try Task.checkCancellation()
            try await maintainer.rollupWeek()

            try Task.checkCancellation()
            try await maintainer.rollupMonth()

            try Task.checkCancellation()
            await maintainer.preGenerateMorningStandup()

            userDefaults.set(runDate, forKey: Self.nightlyRunKey)
            return true
        } catch is CancellationError {
            logger.info("Memory maintenance was cancelled for trigger \(trigger, privacy: .public).")
            return false
        } catch {
            logger.error("Memory maintenance failed for trigger \(trigger, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    func lastSuccessfulNightlyRunAt() -> Date? {
        userDefaults.object(forKey: Self.nightlyRunKey) as? Date
    }

    func lastSuccessfulWeeklyMaintenanceAt() -> Date? {
        userDefaults.object(forKey: Self.weeklyRunKey) as? Date
    }

    func shouldRunNightly(at date: Date) -> Bool {
        guard let lastRun = lastSuccessfulNightlyRunAt() else {
            return true
        }
        return date.timeIntervalSince(lastRun) > 36 * 60 * 60
    }

    func shouldRunWeekly(at date: Date) -> Bool {
        if isSunday(date) {
            return true
        }

        guard let lastWeeklyRun = lastSuccessfulWeeklyMaintenanceAt() else {
            return true
        }
        return date.timeIntervalSince(lastWeeklyRun) > 7 * 24 * 60 * 60
    }

    private func isSunday(_ date: Date) -> Bool {
        calendar.component(.weekday, from: date) == 1
    }
}

protocol BackgroundProcessingTaskHandling: AnyObject {
    var expirationHandler: (() -> Void)? { get set }

    func setTaskCompleted(success: Bool)
}

struct BackgroundProcessingRequest: Equatable {
    let identifier: String
    let earliestBeginDate: Date?
    let requiresExternalPower: Bool
    let requiresNetworkConnectivity: Bool
}

protocol BackgroundTaskScheduling {
    func register(
        identifier: String,
        launchHandler: @escaping (BackgroundProcessingTaskHandling) -> Void
    ) -> Bool

    func submit(_ request: BackgroundProcessingRequest) throws
}

final class SystemBackgroundTaskScheduler: BackgroundTaskScheduling {
    private let scheduler: BGTaskScheduler

    init(scheduler: BGTaskScheduler = .shared) {
        self.scheduler = scheduler
    }

    func register(
        identifier: String,
        launchHandler: @escaping (BackgroundProcessingTaskHandling) -> Void
    ) -> Bool {
        scheduler.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let processingTask = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            launchHandler(SystemBackgroundProcessingTask(task: processingTask))
        }
    }

    func submit(_ request: BackgroundProcessingRequest) throws {
        let taskRequest = BGProcessingTaskRequest(identifier: request.identifier)
        taskRequest.requiresExternalPower = request.requiresExternalPower
        taskRequest.requiresNetworkConnectivity = request.requiresNetworkConnectivity
        taskRequest.earliestBeginDate = request.earliestBeginDate
        try scheduler.submit(taskRequest)
    }
}

final class SystemBackgroundProcessingTask: BackgroundProcessingTaskHandling {
    private let task: BGProcessingTask

    init(task: BGProcessingTask) {
        self.task = task
    }

    var expirationHandler: (() -> Void)? {
        get { task.expirationHandler }
        set { task.expirationHandler = newValue }
    }

    func setTaskCompleted(success: Bool) {
        task.setTaskCompleted(success: success)
    }
}

struct DisabledMemoryTextGenerator: MemoryTextGeneratingClient {
    let hasAPIKeyConfigured = false

    func generateText(
        systemPrompt: String,
        userPrompt: String,
        maxTokens: Int
    ) async throws -> String {
        throw ClaudeClientError.apiError("Memory text generation is disabled.")
    }
}

final class MemoryMaintenanceScheduler {
    static let taskIdentifier = "com.omarelamin.ledger.memory-maintenance"

    private let coordinator: MemoryMaintenanceCoordinator
    private let backgroundTaskScheduler: BackgroundTaskScheduling
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    private let logger = Logger(subsystem: "com.omarelamin.ledger", category: "MemoryScheduler")
    private var didRegisterBackgroundTask = false

    init(
        coordinator: MemoryMaintenanceCoordinator,
        backgroundTaskScheduler: BackgroundTaskScheduling = SystemBackgroundTaskScheduler(),
        calendar: Calendar = .autoupdatingCurrent,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.coordinator = coordinator
        self.backgroundTaskScheduler = backgroundTaskScheduler
        self.calendar = calendar
        self.now = now
    }

    func registerBackgroundTasks() {
        guard !didRegisterBackgroundTask else {
            return
        }

        didRegisterBackgroundTask = backgroundTaskScheduler.register(
            identifier: Self.taskIdentifier
        ) { [weak self] task in
            self?.handleBackgroundTask(task)
        }

        if didRegisterBackgroundTask {
            scheduleNextRun()
        } else {
            logger.error("Failed to register background memory task.")
        }
    }

    func handleScenePhaseChange(_ phase: ScenePhase) {
        guard phase == .active else {
            return
        }

        scheduleNextRun()

        Task {
            _ = await coordinator.runNightlySequence(force: false, trigger: "foreground")
        }
    }

    func scheduleNextRun() {
        let request = BackgroundProcessingRequest(
            identifier: Self.taskIdentifier,
            earliestBeginDate: nextScheduledRun(after: now()),
            requiresExternalPower: true,
            requiresNetworkConnectivity: true
        )

        do {
            try backgroundTaskScheduler.submit(request)
        } catch {
            logger.error("Failed to schedule background memory task: \(error.localizedDescription, privacy: .public)")
        }
    }

    func nextScheduledRun(after date: Date) -> Date {
        let startOfToday = calendar.startOfDay(for: date)
        let todayRun = calendar.date(
            bySettingHour: 3,
            minute: 15,
            second: 0,
            of: startOfToday
        ) ?? startOfToday

        if date < todayRun {
            return todayRun
        }

        return calendar.date(byAdding: .day, value: 1, to: todayRun) ?? todayRun
    }

    private func handleBackgroundTask(_ task: BackgroundProcessingTaskHandling) {
        scheduleNextRun()

        let executionTask = Task {
            let success = await coordinator.runNightlySequence(force: true, trigger: "background")
            if !Task.isCancelled {
                task.setTaskCompleted(success: success)
            }
        }

        task.expirationHandler = { [weak self] in
            executionTask.cancel()
            self?.scheduleNextRun()
        }
    }
}

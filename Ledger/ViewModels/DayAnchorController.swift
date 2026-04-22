import Foundation
import Observation
import SwiftUI
import UIKit

@MainActor
@Observable
final class DayAnchorController {
    var dayAnchor: Date

    private let notificationCenter: NotificationCenter
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (UInt64) async throws -> Void
    private var isSceneActive = false
    private var calendarDayChangeTask: Task<Void, Never>?
    private var significantTimeChangeTask: Task<Void, Never>?
    private var midnightRefreshTask: Task<Void, Never>?

    @Sendable
    private nonisolated static func defaultSleep(_ nanoseconds: UInt64) async throws {
        try await Task.sleep(nanoseconds: nanoseconds)
    }

    init(
        notificationCenter: NotificationCenter = .default,
        calendar: Calendar = .autoupdatingCurrent,
        now: @escaping @Sendable () -> Date = { Date() },
        sleep: @escaping @Sendable (UInt64) async throws -> Void = DayAnchorController.defaultSleep
    ) {
        self.notificationCenter = notificationCenter
        self.calendar = calendar
        self.now = now
        self.sleep = sleep
        self.dayAnchor = calendar.startOfDay(for: now())
        observeTimeChanges()
    }

    func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .active:
            isSceneActive = true
            refreshAnchor()
            scheduleMidnightRefresh()
        case .background, .inactive:
            isSceneActive = false
            midnightRefreshTask?.cancel()
            midnightRefreshTask = nil
        @unknown default:
            isSceneActive = false
            midnightRefreshTask?.cancel()
            midnightRefreshTask = nil
        }
    }

    func refreshAnchor() {
        let latestAnchor = calendar.startOfDay(for: now())
        if latestAnchor != dayAnchor {
            dayAnchor = latestAnchor
        }
    }

    private func observeTimeChanges() {
        calendarDayChangeTask = Task { [weak self] in
            guard let self else { return }
            for await _ in notificationCenter.notifications(named: .NSCalendarDayChanged) {
                await MainActor.run {
                    self.handleExternalTimeChange()
                }
            }
        }

        significantTimeChangeTask = Task { [weak self] in
            guard let self else { return }
            for await _ in notificationCenter.notifications(named: UIApplication.significantTimeChangeNotification) {
                await MainActor.run {
                    self.handleExternalTimeChange()
                }
            }
        }
    }

    private func handleExternalTimeChange() {
        refreshAnchor()
        if isSceneActive {
            scheduleMidnightRefresh()
        }
    }

    private func scheduleMidnightRefresh() {
        midnightRefreshTask?.cancel()
        guard isSceneActive else { return }

        let nextRefreshDate = nextMidnight(after: now())
        let secondsUntilRefresh = max(nextRefreshDate.timeIntervalSince(now()) + 1, 1)
        let sleepNanoseconds = UInt64(secondsUntilRefresh * 1_000_000_000)

        midnightRefreshTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.sleep(sleepNanoseconds)
            } catch {
                return
            }

            await MainActor.run {
                self.refreshAnchor()
                self.scheduleMidnightRefresh()
            }
        }
    }

    private func nextMidnight(after date: Date) -> Date {
        let startOfCurrentDay = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: 1, to: startOfCurrentDay) ?? startOfCurrentDay
    }
}

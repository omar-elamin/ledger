import Foundation
import SwiftUI
import XCTest
@testable import Ledger

@MainActor
final class DayAnchorControllerTests: XCTestCase {
    func testRefreshesOnCalendarDayChangedNotification() async {
        let notificationCenter = NotificationCenter()
        let calendar = makeCalendar()
        let sleeper = TestSleeper()
        var currentDate = date("2026-04-22T10:00:00Z")
        let controller = DayAnchorController(
            notificationCenter: notificationCenter,
            calendar: calendar,
            now: { currentDate },
            sleep: sleeper.sleep
        )

        controller.handleScenePhaseChange(.active)
        await Task.yield()

        currentDate = date("2026-04-23T08:00:00Z")
        notificationCenter.post(name: .NSCalendarDayChanged, object: nil)

        await waitUntil {
            controller.dayAnchor == calendar.startOfDay(for: currentDate)
        }
    }

    func testScheduledMidnightRefreshUsesInjectedSleeper() async {
        let notificationCenter = NotificationCenter()
        let calendar = makeCalendar()
        let sleeper = TestSleeper()
        var currentDate = date("2026-04-22T23:59:00Z")
        let controller = DayAnchorController(
            notificationCenter: notificationCenter,
            calendar: calendar,
            now: { currentDate },
            sleep: sleeper.sleep
        )

        controller.handleScenePhaseChange(.active)
        let capturedDuration = await sleeper.waitForFirstCapture()
        XCTAssertGreaterThan(capturedDuration, 1_000_000_000)

        currentDate = date("2026-04-23T00:00:02Z")
        await sleeper.resumeNext()

        await waitUntil {
            controller.dayAnchor == calendar.startOfDay(for: currentDate)
        }
    }

    private func makeCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ raw: String) -> Date {
        ISO8601DateFormatter().date(from: raw)!
    }
}

actor TestSleeper {
    private var durations: [UInt64] = []
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func sleep(nanoseconds: UInt64) async throws {
        durations.append(nanoseconds)
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func waitForFirstCapture() async -> UInt64 {
        while durations.isEmpty {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return durations[0]
    }

    func resumeNext() {
        guard !continuations.isEmpty else { return }
        continuations.removeFirst().resume()
    }
}

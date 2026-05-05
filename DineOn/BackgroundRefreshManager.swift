#if canImport(BackgroundTasks) && canImport(UIKit) && !os(macOS)
import BackgroundTasks
import Foundation
import UIKit

@MainActor
final class BackgroundRefreshManager {
    static let shared = BackgroundRefreshManager()

    let taskIdentifier = "\(Bundle.main.bundleIdentifier ?? "org.starlightapps.DineOn").menu-refresh"

    private init() {}

    func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            guard let task = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }

            Task { @MainActor in
                self.handleAppRefresh(task)
            }
        }
    }

    func scheduleIfNeeded() {
        guard Preferences.shared.notificationsEnabled else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
            return
        }

        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = earliestRefreshDate()

        do {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
            try BGTaskScheduler.shared.submit(request)
            print("✅ Background refresh scheduled for \(request.earliestBeginDate?.formatted() ?? "later")")
        } catch {
            print("❌ Failed to schedule background refresh: \(error)")
        }
    }

    private func handleAppRefresh(_ task: BGAppRefreshTask) {
        scheduleIfNeeded()

        let refreshTask = Task { @MainActor in
            let targetDateString = NotificationManager.targetDateStrings(
                for: Preferences.shared.notificationTime
            ).first ?? DiningFetcher.formatDate(Date())

            await DiningFetcher.shared.refresh(for: targetDateString)
            await NotificationManager.shared.scheduleDailyNotification()

            if Task.isCancelled {
                task.setTaskCompleted(success: false)
                return
            }

            let state = DiningFetcher.shared.fetchStates[targetDateString]
            let succeeded = state == .loaded || state == .noMenu
            task.setTaskCompleted(success: succeeded)
        }

        task.expirationHandler = {
            refreshTask.cancel()
        }
    }

    private func earliestRefreshDate(from now: Date = Date()) -> Date {
        let notificationDates = NotificationManager.targetDates(
            for: Preferences.shared.notificationTime,
            startingFrom: now,
            count: 1
        )

        guard let targetDate = notificationDates.first else {
            return now.addingTimeInterval(60 * 60)
        }

        let calendar = Calendar.current
        let timeComponents = calendar.dateComponents([.hour, .minute], from: Preferences.shared.notificationTime)
        let fireDate = calendar.date(
            bySettingHour: timeComponents.hour ?? 0,
            minute: timeComponents.minute ?? 0,
            second: 0,
            of: targetDate
        ) ?? targetDate

        let preferredDate = fireDate.addingTimeInterval(-2 * 60 * 60)
        return max(now.addingTimeInterval(60 * 60), preferredDate)
    }
}
#endif

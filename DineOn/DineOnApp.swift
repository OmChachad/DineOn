//
//  DineOnApp.swift
//  DineOn
//
//  Created by Om Chachad on 10/17/25.
//

import SwiftUI

@main
struct DineOnApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
#if canImport(BackgroundTasks) && canImport(UIKit) && !os(macOS)
        BackgroundRefreshManager.shared.register()
#endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    if Preferences.shared.notificationsEnabled {
                        DiningFetcher.shared.prefetchNotificationDates()
                        Task { await NotificationManager.shared.scheduleDailyNotification() }
#if canImport(BackgroundTasks) && canImport(UIKit) && !os(macOS)
                        BackgroundRefreshManager.shared.scheduleIfNeeded()
#endif
                    }
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active, Preferences.shared.notificationsEnabled else { return }

            DiningFetcher.shared.prefetchNotificationDates()
            Task { await NotificationManager.shared.scheduleDailyNotification() }
#if canImport(BackgroundTasks) && canImport(UIKit) && !os(macOS)
            BackgroundRefreshManager.shared.scheduleIfNeeded()
#endif
        }
    }
}

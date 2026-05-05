//
//  NotificationManager.swift
//  DineOn
//
//  Created by Om Chachad on 03/09/26.
//

import Foundation
import UserNotifications

final class NotificationManager {
    static let shared = NotificationManager()
    
    private let notificationIdentifier = "daily-favorites-notification"
    
    private init() {}

    static func targetDates(for notificationTime: Date, startingFrom now: Date = Date(), count: Int = 1) -> [Date] {
        guard count > 0 else { return [] }

        let calendar = Calendar.current
        let timeComponents = calendar.dateComponents([.hour, .minute], from: notificationTime)
        let todayAtNotificationTime = calendar.date(
            bySettingHour: timeComponents.hour ?? 0,
            minute: timeComponents.minute ?? 0,
            second: 0,
            of: now
        ) ?? now

        let firstDate = todayAtNotificationTime > now
            ? now
            : calendar.date(byAdding: .day, value: 1, to: now) ?? now

        return (0..<count).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: firstDate)
        }
    }

    static func targetDateStrings(for notificationTime: Date, startingFrom now: Date = Date(), count: Int = 1) -> [String] {
        targetDates(for: notificationTime, startingFrom: now, count: count).map(DiningFetcher.formatDate)
    }
    
    // MARK: - Permission
    
    func requestPermission(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("❌ Notification permission error: \(error)")
            }
            DispatchQueue.main.async {
                completion(granted)
            }
        }
    }
    
    // MARK: - Scheduling
    
    /// Schedules (or reschedules) the daily favorites notification.
    /// Call this whenever the menu is fetched, favorites change, or notification settings change.
    @MainActor
    func scheduleDailyNotification() async {
        let preferences = Preferences.shared
        
        // Cancel any existing notification first
        cancelNotification()
        
        guard preferences.notificationsEnabled else {
            print("🔕 Notifications disabled, not scheduling.")
            return
        }
        
        guard !preferences.favoriteDishes.isEmpty else {
            print("🔕 No favorite dishes, not scheduling.")
            return
        }
        
        // Determine which date the notification will actually fire on.
        // If the chosen time has already passed today, the calendar trigger
        // will fire tomorrow, so we need tomorrow's menu — not today's.
        let calendar = Calendar.current
        let timeComponents = calendar.dateComponents([.hour, .minute], from: preferences.notificationTime)
        let targetDateString = Self.targetDateStrings(for: preferences.notificationTime).first
            ?? DiningFetcher.formatDate(Date())
        
        // Ensure the target date's menu data is available (fetches from API if needed)
        await DiningFetcher.shared.ensureDataAvailable(for: targetDateString)
        
        guard let menu = DiningFetcher.shared.diningMenu else {
            print("⚠️ No menu data available, cannot schedule notification.")
            return
        }
        
        // Find matches for the date the notification will fire on
        let allMatches = menu.favoriteMatches(for: targetDateString, favorites: preferences.favoriteDishes)
        
        // Filter out meals that will have already expired by the time the notification fires.
        // Uses the same thresholds as MealView: 11+ → Breakfast expired, 17+ → Lunch & Brunch expired.
        let fireHour = timeComponents.hour ?? 0
        let expiredMeals: Set<String> = {
            switch fireHour {
            case 11...16:
                return ["Breakfast"]
            case 17...24:
                return ["Breakfast", "Lunch", "Brunch"]
            default:
                return []
            }
        }()
        let matches = allMatches.filter { !expiredMeals.contains($0.meal) }
        
        guard !matches.isEmpty else {
            print("🔕 No favorite dishes on \(targetDateString), not scheduling notification.")
            return
        }
        
        // Build notification content
        let content = UNMutableNotificationContent()
        content.sound = .default
        
        // Group by (dishName, venue) so the same item at multiple meals merges into "Lunch & Dinner"
        struct DishVenueKey: Hashable {
            let dishName: String
            let venue: String
        }
        
        var mealsPerDishVenue: [DishVenueKey: [String]] = [:]
        for match in matches {
            let key = DishVenueKey(dishName: match.dishName, venue: match.venue)
            mealsPerDishVenue[key, default: []].append(match.meal)
        }
        
        // Sort meals within each group and deduplicate
        struct MergedMatch {
            let dishName: String
            let venue: String
            let meals: String // e.g. "Lunch & Dinner"
        }
        
        let merged: [MergedMatch] = mealsPerDishVenue.map { (key, meals) in
            let sorted = Array(Set(meals)).sorted { (mealOrder[$0] ?? 99) < (mealOrder[$1] ?? 99) }
            let mealsString = sorted.joined(separator: " & ")
            return MergedMatch(dishName: key.dishName, venue: key.venue, meals: mealsString)
        }.sorted { $0.dishName < $1.dishName }
        
        // Count unique dish names for the title
        let uniqueDishes = Set(merged.map { $0.dishName })
        
        if merged.count == 1 {
            let item = merged[0]
            content.title = "🍽️ \(item.dishName) is available!"
            content.body = "\(item.meals) at \(item.venue)"
        } else {
            content.title = "🍽️ \(uniqueDishes.count) favorite\(uniqueDishes.count == 1 ? "" : "s") available today!"
            
            let bodyLines = merged.map { "\($0.dishName) — \($0.meals) at \($0.venue)" }
            content.body = bodyLines.joined(separator: "\n")
        }
        
        // Create a calendar trigger for the user's chosen time
        let trigger = UNCalendarNotificationTrigger(dateMatching: timeComponents, repeats: false)
        
        let request = UNNotificationRequest(
            identifier: notificationIdentifier,
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Failed to schedule notification: \(error)")
            } else {
                print("✅ Notification scheduled for \(timeComponents.hour ?? 0):\(String(format: "%02d", timeComponents.minute ?? 0))")
            }
        }
    }
    
    /// Cancels the pending daily notification.
    func cancelNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationIdentifier])
    }
}

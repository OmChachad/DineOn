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
    func scheduleDailyNotification() {
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
        
        // Try to load cached menu from disk
        guard let menu = loadCachedMenu() else {
            print("⚠️ No cached menu available, cannot schedule notification.")
            return
        }
        
        // Find today's date string
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let todayString = formatter.string(from: Date())
        
        // Find matches
        let matches = menu.favoriteMatches(for: todayString, favorites: preferences.favoriteDishes)
        
        guard !matches.isEmpty else {
            print("🔕 No favorite dishes on today's menu, not scheduling notification.")
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
        
        // Create a calendar trigger for the user's chosen time, repeating daily
        let timeComponents = Calendar.current.dateComponents([.hour, .minute], from: preferences.notificationTime)
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
    
    // MARK: - Cache Loading
    
    /// Loads the cached DiningMenu from disk (same path used by DiningFetcher).
    private func loadCachedMenu() -> DiningMenu? {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let cacheURL = documentsDirectory.appendingPathComponent("diningMenuCache.json")
        
        guard FileManager.default.fileExists(atPath: cacheURL.path) else { return nil }
        
        do {
            let data = try Data(contentsOf: cacheURL)
            return try JSONDecoder().decode(DiningMenu.self, from: data)
        } catch {
            print("❌ Failed to load cached menu for notifications: \(error)")
            return nil
        }
    }
}

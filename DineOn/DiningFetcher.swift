//
//  DiningFetcher.swift
//  DineOn
//
//  Created by Om Chachad on 10/17/25.
//

import Foundation
import Combine

// MARK: - DiningFetcher

@MainActor
class DiningFetcher: ObservableObject {
    static let shared = DiningFetcher()

    @Published var diningMenu: DiningMenu? = nil
    @Published var isLoading: Bool = false

    private let cacheFileName = "diningMenuCache.json"
    private let baseURL = "https://hospitality.usc.edu/wp-json/hsp-api/v1/get-res-dining-menus"

    private var cacheFileURL: URL {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsDirectory.appendingPathComponent(cacheFileName)
    }

    private init() {
        loadCachedMenu()
    }

    // MARK: - Cache

    private func loadCachedMenu() {
        guard FileManager.default.fileExists(atPath: cacheFileURL.path) else {
            print("📦 No cached menu found")
            return
        }

        do {
            let data = try Data(contentsOf: cacheFileURL)
            let cachedMenu = try JSONDecoder().decode(DiningMenu.self, from: data)

            if isMenuValid(cachedMenu) {
                self.diningMenu = cachedMenu
                print("📦 Loaded valid cached menu with dates:", cachedMenu.availableDates)
            } else {
                print("📦 Cached menu expired, clearing cache")
                clearCache()
            }
        } catch {
            print("❌ Failed to load cached menu:", error)
            clearCache()
        }
    }

    private func saveCachedMenu() {
        guard let menu = diningMenu else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(menu)
            try data.write(to: cacheFileURL, options: .atomic)
            print("💾 Menu cached successfully")
        } catch {
            print("❌ Failed to cache menu:", error)
        }
    }

    private func clearCache() {
        do {
            if FileManager.default.fileExists(atPath: cacheFileURL.path) {
                try FileManager.default.removeItem(at: cacheFileURL)
                print("🗑️ Cache cleared")
            }
        } catch {
            print("❌ Failed to clear cache:", error)
        }
    }

    private func isMenuValid(_ menu: DiningMenu) -> Bool {
        let todayString = formatDateString(Calendar.current.startOfDay(for: Date()))
        return menu.availableDates.contains(todayString)
    }

    private func formatDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    // MARK: - Date Helpers

    private func currentWeekDates() -> [String] {
        let calendar = Calendar.current
        let today = Date()
        let weekday = calendar.component(.weekday, from: today) // 1 = Sunday

        guard let startOfWeek = calendar.date(byAdding: .day, value: -(weekday - 1), to: today) else {
            return [formatDateString(today)]
        }

        return (0...7).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: startOfWeek)
                .map { formatDateString($0) }
        }
    }

    // MARK: - API Fetching

    nonisolated private func apiURL(venue: DiningVenue, dateString: String) -> URL? {
        let parts = dateString.split(separator: "-")
        guard parts.count == 3 else { return nil }
        var comps = URLComponents(string: "\(baseURL)/\(venue.apiID)")
        comps?.queryItems = [
            URLQueryItem(name: "y", value: String(parts[0])),
            URLQueryItem(name: "m", value: String(parts[1])),
            URLQueryItem(name: "d", value: String(parts[2]))
        ]
        return comps?.url
    }

    nonisolated private func fetchVenueMenu(venue: DiningVenue, dateString: String) async throws -> [MealName: [StationName: [MenuNode]]]? {
        guard let url = apiURL(venue: venue, dateString: dateString) else { return nil }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty else { return nil }

        guard let apiResponse = try? decodeDiningAPIResponse(from: data),
              let meals = apiResponse.meals, !meals.isEmpty else { return nil }

        return transformToAppFormat(meals: meals)
    }

    nonisolated private func transformToAppFormat(meals: [DiningAPIMeal]) -> [MealName: [StationName: [MenuNode]]] {
        var result: [MealName: [StationName: [MenuNode]]] = [:]
        for meal in meals {
            guard !meal.stations.isEmpty else { continue } // skip meals not served today
            var stationsDict: [StationName: [MenuNode]] = [:]
            for station in meal.stations {
                let nodes: [MenuNode]
                if let subtitle = station.subtitle, !subtitle.isEmpty {
                    let children = station.menu.map { menuNodeFrom($0) }
                    nodes = [MenuNode(name: subtitle, type: .header, allergens: nil, preferences: nil, disclaimers: nil, items: children)]
                } else {
                    nodes = station.menu.map { menuNodeFrom($0) }
                }
                stationsDict[station.station] = nodes
            }
            result[meal.name] = stationsDict
        }
        return result
    }

    nonisolated private func menuNodeFrom(_ item: DiningAPIMenuItem) -> MenuNode {
        let allergens = item.allergens.compactMap { Allergen(rawValue: $0) }
        let preferences = item.preferences.compactMap { DietaryPreference(rawValue: $0) }
        return MenuNode(
            name: item.item,
            type: .item,
            allergens: allergens.isEmpty ? nil : allergens,
            preferences: preferences.isEmpty ? nil : preferences,
            disclaimers: nil,
            items: nil
        )
    }

    // MARK: - Public API

    /// Fetches the dining menu for the current week, using cache if valid.
    func fetchDiningMenu(forceRefresh: Bool = false) {
        if !forceRefresh, let menu = diningMenu, isMenuValid(menu) {
            print("📦 Using cached menu - still valid for today")
            return
        }

        Task {
            isLoading = true
            defer { isLoading = false }

            let weekDates = currentWeekDates()
            var allData: DiningData = [:]

            await withTaskGroup(of: (String, DiningVenue, [MealName: [StationName: [MenuNode]]]?).self) { group in
                for dateString in weekDates {
                    for venue in DiningVenue.allCases {
                        group.addTask { [self] in
                            let result = try? await self.fetchVenueMenu(venue: venue, dateString: dateString)
                            return (dateString, venue, result)
                        }
                    }
                }

                for await (dateString, venue, venueMenu) in group {
                    if let venueMenu {
                        if allData[dateString] == nil { allData[dateString] = [:] }
                        allData[dateString]?[venue.rawValue] = venueMenu
                    }
                }
            }

            guard !allData.isEmpty else {
                print("❌ No menu data fetched from API")
                return
            }

            self.diningMenu = DiningMenu(data: allData)
            saveCachedMenu()

            if Preferences.shared.notificationsEnabled {
                NotificationManager.shared.scheduleDailyNotification()
            }

            print("✅ Menu fetched. Available dates:", self.diningMenu?.availableDates ?? [])
        }
    }

    /// Refreshes the menu for a specific date (expects "yyyy-MM-dd").
    func refreshMenu(for dateString: String) async {
        isLoading = true
        defer { isLoading = false }

        print("🔄 Refreshing menus for date:", dateString)

        var dateVenueData: [VenueName: [MealName: [StationName: [MenuNode]]]] = [:]

        await withTaskGroup(of: (DiningVenue, [MealName: [StationName: [MenuNode]]]?).self) { group in
            for venue in DiningVenue.allCases {
                group.addTask { [self] in
                    let result = try? await self.fetchVenueMenu(venue: venue, dateString: dateString)
                    return (venue, result)
                }
            }

            for await (venue, venueMenu) in group {
                if let venueMenu {
                    dateVenueData[venue.rawValue] = venueMenu
                }
            }
        }

        guard !dateVenueData.isEmpty else {
            print("❌ No menu data fetched for \(dateString)")
            return
        }

        if diningMenu == nil {
            diningMenu = DiningMenu(data: [dateString: dateVenueData])
        } else {
            diningMenu!.data[dateString] = dateVenueData
        }

        saveCachedMenu()

        if Preferences.shared.notificationsEnabled {
            NotificationManager.shared.scheduleDailyNotification()
        }

        print("✅ Refresh for \(dateString) complete.")
    }
}

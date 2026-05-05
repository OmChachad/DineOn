//
//  DiningFetcher.swift
//  DineOn
//
//  Created by Om Chachad on 10/17/25.
//

import Foundation
import Combine
import Network

// MARK: - Per-Date Fetch State

enum DateFetchState: Equatable {
    case idle
    case loading
    case loaded
    case noMenu
    case error(String)
}

// MARK: - DiningFetcher

@MainActor
class DiningFetcher: ObservableObject {
    static let shared = DiningFetcher()

    /// Live in-memory menu data, keyed by date string ("yyyy-MM-dd").
    @Published var menuData: DiningData = [:]

    /// Per-date loading / error state so the UI can react individually.
    @Published var fetchStates: [String: DateFetchState] = [:]

    private let baseURL = "https://hospitality.usc.edu/wp-json/hsp-api/v1/get-res-dining-menus"

    // Network monitor
    private let monitor = NWPathMonitor()
    private var isOnline: Bool = true

    // MARK: - Computed helpers

    /// Thin wrapper so the rest of the app can keep using `.diningMenu`.
    var diningMenu: DiningMenu? {
        menuData.isEmpty ? nil : DiningMenu(data: menuData)
    }

    // MARK: - Init

    private init() {
        startNetworkMonitor()
        loadAllCachedDates()
        evictPastCaches()

        // Eagerly seed today's data
        let today = Self.formatDate(Date())
        fetchMenu(for: today)
    }

    // MARK: - Network Monitor

    private func startNetworkMonitor() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isOnline = (path.status == .satisfied)
            }
        }
        monitor.start(queue: DispatchQueue(label: "DineOn.NetworkMonitor"))
    }

    // MARK: - Public API

    /// Fetches menu data for the given date.
    /// - Online: always hits the API, updates in-memory data + disk cache.
    /// - Offline: serves from disk cache if available.
    func fetchMenu(for dateString: String) {
        guard fetchStates[dateString] != .loading else { return }

        if !isOnline {
            // Offline path — use cache or report error
            if menuData[dateString] != nil {
                fetchStates[dateString] = .loaded
            } else if let cached = Self.loadCache(for: dateString) {
                menuData[dateString] = cached
                fetchStates[dateString] = .loaded
            } else {
                fetchStates[dateString] = .error("You're offline and no cached menu is available.")
            }
            return
        }

        // Online — hit the API
        Task { await fetchFromAPI(for: dateString) }
    }

    /// Pull-to-refresh variant. Always hits the API.
    func refresh(for dateString: String) async {
        guard isOnline else { return }
        await fetchFromAPI(for: dateString)
    }

    /// Ensures data for the given date is available in `menuData`.
    /// If already loaded, returns immediately. Otherwise fetches from API (or cache if offline).
    func ensureDataAvailable(for dateString: String) async {
        if menuData[dateString] != nil { return }

        if isOnline {
            await fetchFromAPI(for: dateString)
        } else if let cached = Self.loadCache(for: dateString) {
            menuData[dateString] = cached
            fetchStates[dateString] = .loaded
        }
    }

    // MARK: - API Fetch

    private func fetchFromAPI(for dateString: String) async {
        fetchStates[dateString] = .loading

        var venueResults: [VenueName: [MealName: [StationName: [MenuNode]]]] = [:]

        await withTaskGroup(of: (DiningVenue, [MealName: [StationName: [MenuNode]]]?).self) { group in
            for venue in DiningVenue.allCases {
                group.addTask { [self] in
                    let result = try? await self.fetchVenueMenu(venue: venue, dateString: dateString)
                    return (venue, result)
                }
            }
            for await (venue, venueMenu) in group {
                if let venueMenu { venueResults[venue.rawValue] = venueMenu }
            }
        }

        if venueResults.isEmpty {
            fetchStates[dateString] = isOnline ? .noMenu : .error("Network error.")
            return
        }

        menuData[dateString] = venueResults
        fetchStates[dateString] = .loaded
        Self.saveCache(for: dateString, data: venueResults)

        if Preferences.shared.notificationsEnabled {
            Task { await NotificationManager.shared.scheduleDailyNotification() }
        }
    }

    // MARK: - API Helpers (nonisolated for TaskGroup)

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
            guard !meal.stations.isEmpty else { continue }
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

    // MARK: - Per-Date Disk Cache

    nonisolated private static var cacheDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DiningMenuCache", isDirectory: true)
    }

    nonisolated private static func cacheURL(for dateString: String) -> URL {
        cacheDirectory.appendingPathComponent("menu-\(dateString).json")
    }

    nonisolated private static func loadCache(for dateString: String) -> [VenueName: [MealName: [StationName: [MenuNode]]]]? {
        guard let data = try? Data(contentsOf: cacheURL(for: dateString)) else { return nil }
        return try? JSONDecoder().decode([VenueName: [MealName: [StationName: [MenuNode]]]].self, from: data)
    }

    nonisolated private static func saveCache(for dateString: String, data: [VenueName: [MealName: [StationName: [MenuNode]]]]) {
        let fm = FileManager.default
        let dir = cacheDirectory
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        if let encoded = try? JSONEncoder().encode(data) {
            try? encoded.write(to: cacheURL(for: dateString), options: .atomic)
        }
    }

    /// Loads all cached dates into memory (offline seed on launch).
    private func loadAllCachedDates() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: Self.cacheDirectory, includingPropertiesForKeys: nil) else { return }
        for file in files where file.pathExtension == "json" {
            let name = file.deletingPathExtension().lastPathComponent
            let dateString = String(name.dropFirst("menu-".count))
            if let cached = Self.loadCache(for: dateString) {
                menuData[dateString] = cached
                fetchStates[dateString] = .loaded
            }
        }
    }

    /// Removes cached files for dates before today.
    private func evictPastCaches() {
        let fm = FileManager.default
        let today = Self.formatDate(Date())
        guard let files = try? fm.contentsOfDirectory(at: Self.cacheDirectory, includingPropertiesForKeys: nil) else { return }
        for file in files where file.pathExtension == "json" {
            let name = file.deletingPathExtension().lastPathComponent
            let dateString = String(name.dropFirst("menu-".count))
            if dateString < today {
                try? fm.removeItem(at: file)
                menuData.removeValue(forKey: dateString)
                fetchStates.removeValue(forKey: dateString)
            }
        }
    }

    // MARK: - Date Formatting

    nonisolated static func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}

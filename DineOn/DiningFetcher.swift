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

private enum VenueFetchResult {
    case menu([MealName: [StationName: [MenuNode]]])
    case noMenu
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

    /// Proactively loads the next notification dates so alerts don't depend on
    /// the user manually opening future days in the UI first.
    func prefetchNotificationDates(count: Int = 2) {
        guard Preferences.shared.notificationsEnabled else { return }

        let targetDates = NotificationManager.targetDateStrings(
            for: Preferences.shared.notificationTime,
            count: count
        )

        for dateString in targetDates {
            fetchMenu(for: dateString)
        }
    }

    // MARK: - API Fetch

    private func fetchFromAPI(for dateString: String) async {
        fetchStates[dateString] = .loading

        let hadExistingData = menuData[dateString] != nil
        var venueResults: [VenueName: [MealName: [StationName: [MenuNode]]]] = [:]
        var hadSuccessfulVenueResponse = false

        await withTaskGroup(of: (DiningVenue, VenueFetchResult?).self) { group in
            for venue in DiningVenue.allCases {
                group.addTask { [self] in
                    let result = try? await self.fetchVenueMenu(venue: venue, dateString: dateString)
                    return (venue, result)
                }
            }
            for await (venue, result) in group {
                guard let result else { continue }
                hadSuccessfulVenueResponse = true

                switch result {
                case .menu(let venueMenu):
                    venueResults[venue.rawValue] = venueMenu
                case .noMenu:
                    break
                }
            }
        }

        if !venueResults.isEmpty {
            menuData[dateString] = venueResults
            fetchStates[dateString] = .loaded
            Self.saveCache(for: dateString, data: venueResults)

            if Preferences.shared.notificationsEnabled {
                Task { await NotificationManager.shared.scheduleDailyNotification() }
            }
            return
        }

        if hadSuccessfulVenueResponse {
            menuData.removeValue(forKey: dateString)
            fetchStates[dateString] = .noMenu
            Self.removeCache(for: dateString)
            return
        }

        fetchStates[dateString] = hadExistingData
            ? .loaded
            : .error("Couldn't load menu right now.")
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

    nonisolated private func fetchVenueMenu(venue: DiningVenue, dateString: String) async throws -> VenueFetchResult {
        guard let url = apiURL(venue: venue, dateString: dateString) else {
            throw URLError(.badURL)
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty else {
            throw URLError(.badServerResponse)
        }

        let apiResponse = try decodeDiningAPIResponse(from: data)
        guard let meals = apiResponse.meals else { return .noMenu }
        let transformed = transformToAppFormat(meals: meals)

        return transformed.isEmpty ? .noMenu : .menu(transformed)
    }

    nonisolated private func transformToAppFormat(meals: [DiningAPIMeal]) -> [MealName: [StationName: [MenuNode]]] {
        var result: [MealName: [StationName: [MenuNode]]] = [:]
        for meal in meals {
            guard !meal.stations.isEmpty else { continue }
            var stationsDict: [StationName: [MenuNode]] = [:]
            for station in meal.stations {
                let stationWarningNode = stationWarningNode(from: station.menu)
                let menuItems = station.menu.filter { !isNutsAndPeanutsWarningText($0.item) }
                let groupedMenu = groupedMenuNodes(from: menuItems)
                let contentNodes: [MenuNode]
                if let subtitle = station.subtitle, !subtitle.isEmpty {
                    let children = groupedMenu
                    contentNodes = [MenuNode(name: subtitle, type: .header, allergens: nil, preferences: nil, disclaimers: nil, timingInfo: nil, items: children)]
                } else {
                    contentNodes = groupedMenu
                }
                let nodes = stationWarningNode.map { [$0] + contentNodes } ?? contentNodes
                stationsDict[station.station] = nodes
            }
            result[meal.name] = stationsDict
        }
        return result
    }

    nonisolated private func groupedMenuNodes(from items: [DiningAPIMenuItem]) -> [MenuNode] {
        var nodes: [MenuNode] = []
        var currentSection: PendingSection?

        func flushCurrentSection() {
            guard let section = currentSection else { return }

            nodes.append(
                MenuNode(
                    name: section.title,
                    type: .header,
                    allergens: nil,
                    preferences: nil,
                    disclaimers: nil,
                    timingInfo: section.timingInfo,
                    items: section.items.isEmpty ? nil : section.items
                )
            )

            currentSection = nil
        }

        for item in items {
            switch parsedMenuEntry(from: item) {
            case .header(let title, let timingInfo):
                flushCurrentSection()
                currentSection = PendingSection(title: title, timingInfo: timingInfo, items: [])
            case .info(let title, let timingInfo):
                if title.isEmpty, var section = currentSection {
                    section = PendingSection(title: section.title, timingInfo: timingInfo, items: section.items)
                    currentSection = section
                } else {
                    flushCurrentSection()
                    nodes.append(
                        MenuNode(
                            name: title,
                            type: .info,
                            allergens: nil,
                            preferences: nil,
                            disclaimers: nil,
                            timingInfo: timingInfo,
                            items: nil
                        )
                    )
                }
            case .item:
                let node = menuNodeFrom(item)
                if var section = currentSection {
                    section.items.append(node)
                    currentSection = section
                } else {
                    nodes.append(node)
                }
            }
        }

        flushCurrentSection()
        return nodes
    }

    nonisolated private func parsedMenuEntry(from item: DiningAPIMenuItem) -> ParsedMenuEntry {
        let trimmed = item.item.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .item }
        guard item.allergens.isEmpty, item.preferences.isEmpty else { return .item }

        if let parsedTimingLine = parsedTimingLine(from: trimmed) {
            switch parsedTimingLine {
            case .statusOnly(let timingInfo):
                return .info(title: "", timingInfo: timingInfo)
            case .titled(let title, let timingInfo):
                return isAllCapsTitle(title)
                    ? .header(title: title, timingInfo: timingInfo)
                    : .info(title: title, timingInfo: timingInfo)
            }
        }

        return isAllCapsTitle(trimmed) ? .header(title: trimmed, timingInfo: nil) : .item
    }

    nonisolated private func parsedTimingLine(from text: String) -> ParsedTimingLine? {
        let patterns: [(String, MenuTimingKind)] = [
            ("^STATION\\s+OPENS\\s+AT\\s+(.+)$", .opensAt),
            ("^(.+?)\\s*\\(?AVAILABLE\\s+UNTIL\\s+(.+?)\\)?$", .availableUntil),
            ("^(.+?)\\s*\\(?AVAILABLE\\s+FROM\\s+(.+?)\\)?$", .availableFrom),
            ("^(.+?)\\s*\\(?AVAILABLE\\s+AT\\s+(.+?)\\)?$", .availableAt),
            ("^(.+?)\\s*\\(?SERVED\\s+AT\\s+(.+?)\\)?$", .servedAt),
            ("^(.+?)\\s*\\(?OPENS\\s+AT\\s+(.+?)\\)?$", .opensAt)
        ]

        for (pattern, kind) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            guard let match = regex.firstMatch(in: text, options: [], range: range) else { continue }

            if match.numberOfRanges == 2,
               let timeRange = Range(match.range(at: 1), in: text) {
                return .statusOnly(
                    MenuTimingInfo(
                        kind: kind,
                        timeText: normalizedTimeText(from: String(text[timeRange]))
                    )
                )
            }

            if match.numberOfRanges >= 3,
               let titleRange = Range(match.range(at: 1), in: text),
               let timeRange = Range(match.range(at: 2), in: text) {
                let title = cleanedHeaderTitle(String(text[titleRange]))
                let timeText = normalizedTimeText(from: String(text[timeRange]))

                guard !timeText.isEmpty else { return nil }
                if title.isEmpty || title.uppercased() == "STATION" {
                    return .statusOnly(MenuTimingInfo(kind: kind, timeText: timeText))
                }
                return .titled(title: title, timingInfo: MenuTimingInfo(kind: kind, timeText: timeText))
            }
        }

        return nil
    }

    nonisolated private func cleanedHeaderTitle(_ title: String) -> String {
        title
            .trimmingCharacters(in: CharacterSet(charactersIn: " ()").union(.whitespacesAndNewlines))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    nonisolated private func normalizedTimeText(from text: String) -> String {
        text
            .trimmingCharacters(in: CharacterSet(charactersIn: " ()").union(.whitespacesAndNewlines))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    nonisolated private func isAllCapsTitle(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let words = trimmed.split(whereSeparator: \.isWhitespace)
        guard words.count >= 1 else { return false }

        let letters = trimmed.unicodeScalars.filter(CharacterSet.letters.contains)
        guard !letters.isEmpty else { return false }

        return letters.allSatisfy { CharacterSet.uppercaseLetters.contains($0) }
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
            timingInfo: nil,
            items: nil
        )
    }

    nonisolated private func stationWarningNode(from items: [DiningAPIMenuItem]) -> MenuNode? {
        guard let warningItem = items.first(where: { isNutsAndPeanutsWarningText($0.item) }) else {
            return nil
        }

        return MenuNode(
            name: displayNutsAndPeanutsWarning(warningItem.item),
            type: .info,
            allergens: nil,
            preferences: nil,
            disclaimers: [stationWarningDisclaimerMarker],
            timingInfo: nil,
            items: nil
        )
    }

    private struct PendingSection {
        let title: String
        let timingInfo: MenuTimingInfo?
        var items: [MenuNode]
    }

    private enum ParsedMenuEntry {
        case item
        case header(title: String, timingInfo: MenuTimingInfo?)
        case info(title: String, timingInfo: MenuTimingInfo)
    }

    private enum ParsedTimingLine {
        case statusOnly(MenuTimingInfo)
        case titled(title: String, timingInfo: MenuTimingInfo)
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

    nonisolated private static func removeCache(for dateString: String) {
        try? FileManager.default.removeItem(at: cacheURL(for: dateString))
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

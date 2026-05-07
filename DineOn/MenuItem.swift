//
//  MenuItem.swift
//  DineOn
//
//  Created by Om Chachad on 10/17/25.
//


//
//  DiningMenu.swift
//  Created by ChatGPT on 2025-10-17
//

import Foundation
import SwiftUI
// MARK: - Enums

/// The type of a menu node (item, header, or time header).
enum MenuNodeType: String, Codable {
    case item
    case header
    case timeHeader = "time-header"
    case info
}

enum MenuTimingKind: String, Codable, Hashable {
    case opensAt = "opens-at"
    case availableAt = "available-at"
    case availableUntil = "available-until"
    case availableFrom = "available-from"
    case servedAt = "served-at"
}

struct MenuTimingInfo: Codable, Hashable {
    let kind: MenuTimingKind
    let timeText: String
}

/// Optional dietary flags (from JS `data-preferences`)
enum DietaryPreference: String, Codable, Attribute, CaseIterable {
    case vegan
    case vegetarian
    case halalIngredients = "halal-ingredients"
    case unknown
}

/// Common allergen categories (from JS `data-allergens`)
enum Allergen: String, Codable, Attribute, CaseIterable {
    case dairy, eggs, soy, gluten, sesame, fish, shellfish, pork, peanuts, treeNuts = "tree-nuts"
    case notAnalyzed = "not-analyzed"
    case unknown
}

protocol Attribute {
    
}

func imageFor<T: Attribute & RawRepresentable>(_ value: T) -> Image where T.RawValue == String {
    return Image(value.rawValue)
}


// MARK: - Models

/// Represents a single menu entry, which can be an item or a group (header/time-header).
struct MenuNode: Codable, Hashable {
    let name: String
    let type: MenuNodeType
    let allergens: [Allergen]?
    let preferences: [DietaryPreference]?
    let disclaimers: [String]?
    let timingInfo: MenuTimingInfo?
    let items: [MenuNode]?
}

// Outer hierarchy
typealias DiningData = [String: [VenueName: [MealName: [StationName: [MenuNode]]]]]

/// Just type aliases for better readability
typealias VenueName = String
typealias MealName = String
typealias StationName = String

let mealOrder: [String: Int] = [
    "Breakfast": 1,
    "Brunch": 2,
    "Lunch": 3,
    "Dinner": 4
]

let allergenAwarenessZoneStationMarker = "Allergen Awareness Zone"
let allergenAwarenessZoneAccessSuffix = "(must register for access)"

struct MenuVisibilityPreferences {
    let hasAAZAccess: Bool
    let hasDietaryRestrictions: Bool
    let selectedAllergens: Set<Allergen>
    let selectedDietaryPreferences: Set<DietaryPreference>
    let excludedKeywords: Set<String>
    let favoriteDishes: Set<String>

    init(
        hasAAZAccess: Bool,
        hasDietaryRestrictions: Bool,
        selectedAllergens: Set<Allergen>,
        selectedDietaryPreferences: Set<DietaryPreference>,
        excludedKeywords: Set<String>,
        favoriteDishes: Set<String>
    ) {
        self.hasAAZAccess = hasAAZAccess
        self.hasDietaryRestrictions = hasDietaryRestrictions
        self.selectedAllergens = selectedAllergens
        self.selectedDietaryPreferences = selectedDietaryPreferences
        self.excludedKeywords = Set(
            excludedKeywords
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        )
        self.favoriteDishes = favoriteDishes
    }

    init(preferences: Preferences) {
        self.init(
            hasAAZAccess: preferences.hasAAZAccess,
            hasDietaryRestrictions: preferences.hasDietaryRestrictions,
            selectedAllergens: Set(preferences.selectedAllergens.compactMap(Allergen.init(rawValue:))),
            selectedDietaryPreferences: Set(preferences.selectedDietaryPreferences.compactMap(DietaryPreference.init(rawValue:))),
            excludedKeywords: preferences.excludedKeywords,
            favoriteDishes: preferences.favoriteDishes
        )
    }

    func isFavorite(_ itemName: String) -> Bool {
        let normalizedItem = itemName.lowercased()
        return favoriteDishes.contains { favorite in
            normalizedItem.contains(favorite.lowercased())
        }
    }
}

func isAAZStation(_ stationName: String) -> Bool {
    stationName.localizedCaseInsensitiveContains(allergenAwarenessZoneStationMarker)
}

func displayStationName(_ stationName: String, hasAAZAccess: Bool) -> String {
    guard hasAAZAccess, isAAZStation(stationName) else { return stationName }

    return stationName
        .replacingOccurrences(of: allergenAwarenessZoneAccessSuffix, with: "", options: .caseInsensitive)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

func isAAZNode(_ node: MenuNode) -> Bool {
    node.name
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .localizedCaseInsensitiveContains("AAZ ")
}

func shouldDisplayNode(_ node: MenuNode, preferences: MenuVisibilityPreferences) -> Bool {
    preferences.hasAAZAccess || !isAAZNode(node)
}

func itemFitsPreferences(_ node: MenuNode, preferences: MenuVisibilityPreferences) -> Bool {
    let normalizedName = node.name.lowercased()
    if preferences.excludedKeywords.contains(where: normalizedName.contains) {
        return false
    }

    let nodeAllergens = Set(node.allergens ?? [])
    if !preferences.selectedAllergens.isDisjoint(with: nodeAllergens) {
        return false
    }

    guard preferences.hasDietaryRestrictions else {
        return true
    }

    let nodePreferences = Set(node.preferences ?? [])
    for preference in preferences.selectedDietaryPreferences {
        switch preference {
        case .vegetarian:
            guard nodePreferences.contains(.vegetarian) || nodePreferences.contains(.vegan) else {
                return false
            }
        case .vegan:
            guard nodePreferences.contains(.vegan) else {
                return false
            }
        default:
            guard nodePreferences.contains(preference) else {
                return false
            }
        }
    }

    return true
}

let nutsAndPeanutsWarningText = "*NUTS AND PEANUTS ARE USED HERE*"
let stationWarningDisclaimerMarker = "station-warning"

func isNutsAndPeanutsWarningText(_ text: String) -> Bool {
    text.trimmingCharacters(in: .whitespacesAndNewlines) == nutsAndPeanutsWarningText
}

func isStationWarningNode(_ node: MenuNode) -> Bool {
    (node.type == .info && (node.disclaimers ?? []).contains(stationWarningDisclaimerMarker))
        || isNutsAndPeanutsWarningText(node.name)
}

func displayNutsAndPeanutsWarning(_ text: String) -> String {
    text
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .trimmingCharacters(in: CharacterSet(charactersIn: "*"))
}

func stationWarningDisplayText(for node: MenuNode) -> String {
    displayNutsAndPeanutsWarning(node.name)
}

func expiredMealNames(for chosenDate: String, now: Date = .now) -> Set<String> {
    guard chosenDate == DiningFetcher.formatDate(now) else {
        return []
    }

    switch Calendar.current.component(.hour, from: now) {
    case 11...16:
        return ["Breakfast"]
    case 17...24:
        return ["Breakfast", "Lunch", "Brunch"]
    default:
        return []
    }
}

func visibleMealNames(from meals: [String], chosenDate: String, now: Date = .now) -> [String] {
    let expired = expiredMealNames(for: chosenDate, now: now)
    return meals
        .filter { !expired.contains($0) }
        .sorted { (mealOrder[$0] ?? 99) < (mealOrder[$1] ?? 99) }
}

// MARK: - Wrapper

struct DiningMenu: Codable {
    var data: DiningData

    /// All available dates in the dataset.
    var availableDates: [String] {
        Array(data.keys).sorted()
    }

    /// All venues for a given date.
    func venues(for date: String) -> [String] {
        guard let keys = data[date]?.keys else { return [] }
        return Array(keys)
    }

    /// All meals for a given venue and date.
    func meals(for date: String, venue: String) -> [String] {
        guard let keys = data[date]?[venue]?.keys else { return [] }
        return Array(keys)
    }

    /// All stations for a given meal.
    func stations(for date: String, venue: String, meal: String) -> [String] {
        guard let keys = data[date]?[venue]?[meal]?.keys else { return [] }
        return Array(keys)
    }

    /// All nodes (items, headers, etc.) for a specific station.
    func nodes(for date: String, venue: String, meal: String, station: String) -> [MenuNode]? {
        data[date]?[venue]?[meal]?[station]
    }

    /// Flattens all items for a meal across all stations.
    func allItems(for date: String, venue: String, meal: String) -> [MenuNode] {
        guard let stations = data[date]?[venue]?[meal] else { return [] }
        return stations.values.flatMap { $0 }
    }
    
    /// A single match of a favorited dish found on the menu.
    struct FavoriteMatch: Hashable {
        let dishName: String
        let meal: String
        let venue: String
    }
    
    /// Finds all favorite dishes that appear on the menu for a given date.
    func favoriteMatches(for date: String, favorites: Set<String>) -> [FavoriteMatch] {
        guard !favorites.isEmpty, let venuesDict = data[date] else { return [] }
        
        let lowercasedFavorites = favorites.map { $0.lowercased() }
        var matches: [FavoriteMatch] = []
        
        for (venue, mealsDict) in venuesDict {
            for (meal, stationsDict) in mealsDict {
                for (_, nodes) in stationsDict {
                    let itemNames = Self.collectItemNames(from: nodes)
                    for itemName in itemNames {
                        let lowerItem = itemName.lowercased()
                        for fav in lowercasedFavorites {
                            if lowerItem.contains(fav) {
                                matches.append(FavoriteMatch(dishName: itemName, meal: meal, venue: venue))
                            }
                        }
                    }
                }
            }
        }
        
        // Remove duplicates
        return Array(Set(matches))
    }
    
    /// Recursively collects all item names from a list of menu nodes.
    private static func collectItemNames(from nodes: [MenuNode]) -> [String] {
        var names: [String] = []
        for node in nodes {
            switch node.type {
            case .item:
                names.append(node.name)
            case .info:
                break
            case .header, .timeHeader:
                if let children = node.items {
                    names.append(contentsOf: collectItemNames(from: children))
                }
            }
        }
        return names
    }
}

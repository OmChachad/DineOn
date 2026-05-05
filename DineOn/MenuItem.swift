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

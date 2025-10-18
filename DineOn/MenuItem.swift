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
    let data: DiningData

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
}

// MARK: - Parser

enum DiningMenuParser {
    static func parse(from any: Any) throws -> DiningMenu {
        let data = try JSONSerialization.data(withJSONObject: any, options: [])
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(DiningData.self, from: data)
        return DiningMenu(data: decoded)
    }

    static func parse(from string: String) throws -> DiningMenu {
        let cleaned = cleanAppleStyleString(string)
        guard let data = cleaned.data(using: .utf8) else {
            throw NSError(domain: "DiningMenuParser", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid UTF-8"])
        }
        let decoded = try JSONDecoder().decode(DiningData.self, from: data)
        return DiningMenu(data: decoded)
    }

    private static func cleanAppleStyleString(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: " = ", with: ": ")
            .replacingOccurrences(of: ";", with: ",")
            .replacingOccurrences(of: "(", with: "[")
            .replacingOccurrences(of: ")", with: "]")
    }
}

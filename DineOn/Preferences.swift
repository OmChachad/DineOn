//
//  Preferences.swift
//  DineOn
//
//  Created by Om Chachad on 10/17/25.
//


import SwiftUI
import Combine

final class Preferences: ObservableObject {
    static let shared = Preferences()
    
    private init() {
        // Load saved values from UserDefaults
        self.selectedAllergens = Set(UserDefaults.standard.stringArray(forKey: "selectedAllergens") ?? [])
        self.selectedDietaryPreferences = Set(UserDefaults.standard.stringArray(forKey: "selectedDietaryPreferences") ?? [])
        self.excludedKeywords = Set(UserDefaults.standard.stringArray(forKey: "excludedKeywords") ?? [])
        self.hasDietaryRestrictions = UserDefaults.standard.bool(forKey: "hasDietaryRestrictions")
        self.favoriteDishes = Set(UserDefaults.standard.stringArray(forKey: "favoriteDishes") ?? [])
    }

    // MARK: - Published properties
    @Published var hasDietaryRestrictions: Bool {
        didSet {
            UserDefaults.standard.set(hasDietaryRestrictions, forKey: "hasDietaryRestrictions")
        }
    }

    @Published var selectedAllergens: Set<String> {
        didSet {
            UserDefaults.standard.set(Array(selectedAllergens), forKey: "selectedAllergens")
        }
    }

    @Published var selectedDietaryPreferences: Set<String> {
        didSet {
            UserDefaults.standard.set(Array(selectedDietaryPreferences), forKey: "selectedDietaryPreferences")
        }
    }

    @Published var excludedKeywords: Set<String> {
        didSet {
            UserDefaults.standard.set(Array(excludedKeywords), forKey: "excludedKeywords")
        }
    }
    
    @Published var favoriteDishes: Set<String> {
        didSet {
            UserDefaults.standard.set(Array(favoriteDishes), forKey: "favoriteDishes")
        }
    }

    // MARK: - Convenience methods
    func toggleAllergen(_ allergen: Allergen) {
        if selectedAllergens.contains(allergen.rawValue) {
            selectedAllergens.remove(allergen.rawValue)
        } else {
            selectedAllergens.insert(allergen.rawValue)
        }
    }

    func toggleDietaryPreference(_ preference: DietaryPreference) {
        if selectedDietaryPreferences.contains(preference.rawValue) {
            selectedDietaryPreferences.remove(preference.rawValue)
        } else {
            selectedDietaryPreferences.insert(preference.rawValue)
        }
    }
    
    func isAllergenSelected(_ allergen: Allergen) -> Bool {
        selectedAllergens.contains(allergen.rawValue)
    }

    func isDietaryPreferenceSelected(_ preference: DietaryPreference) -> Bool {
        selectedDietaryPreferences.contains(preference.rawValue)
    }

    func toggleExcludedKeyword(_ keyword: String) {
        let lower = keyword.lowercased()
        if excludedKeywords.contains(lower) {
            excludedKeywords.remove(lower)
        } else {
            excludedKeywords.insert(lower)
        }
    }

    func isKeywordExcluded(_ keyword: String) -> Bool {
        excludedKeywords.contains(keyword.lowercased())
    }

    /// Returns true if this food name matches any excluded keyword
    func isFoodExcludedByName(_ name: String) -> Bool {
        let lowerName = name.lowercased()
        return excludedKeywords.contains(where: { lowerName.contains($0) })
    }
    
    func toggleFavoriteDish(_ dishName: String) {
        if favoriteDishes.contains(dishName) {
            favoriteDishes.remove(dishName)
        } else {
            favoriteDishes.insert(dishName)
        }
    }
    
    func isDishFavorited(_ dishName: String) -> Bool {
        favoriteDishes.contains(dishName)
    }
}

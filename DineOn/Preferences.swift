//
//  Preferences.swift
//  DineOn
//
//  Created by Om Chachad on 10/17/25.
//


import SwiftUI
internal import Combine

final class Preferences: ObservableObject {
    static let shared = Preferences()
    private init() {
        // Load saved values from UserDefaults
        self.selectedAllergens = Set(UserDefaults.standard.stringArray(forKey: "selectedAllergens") ?? [])
        self.selectedDietaryPreferences = Set(UserDefaults.standard.stringArray(forKey: "selectedDietaryPreferences") ?? [])
        self.hasDietaryRestrictions = UserDefaults.standard.bool(forKey: "hasDietaryRestrictions")
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
}

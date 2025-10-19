//
//  PreferencesView.swift
//  DineOn
//
//  Created by Om Chachad on 10/17/25.
//

import SwiftUI

struct PreferencesView: View {
    @StateObject private var preferences = Preferences.shared
    
    @State private var newKeyword: String = ""
    
    var body: some View {
        Form {
            Section("Allergens") {
                DisclosureGroup("Allergens") {
                    ForEach(Allergen.allCases.filter({ $0 != .notAnalyzed && $0 != .unknown }), id: \.self) { allergen in
                        Toggle(isOn: Binding(
                            get: { preferences.isAllergenSelected(allergen) },
                            set: { _ in preferences.toggleAllergen(allergen) }
                        )) {
                            HStack {
                                imageFor(allergen)
                                    .resizable()
                                    .frame(width: 20, height: 20)
                                Text(allergen.rawValue.replacingOccurrences(of: "-", with: " ").capitalized)
                            }
                        }
                    }
                }
            }

            Section("Dietary Preferences") {
                Toggle("Enable Dietary Preferences", isOn: $preferences.hasDietaryRestrictions)
                
                if preferences.hasDietaryRestrictions {
                    ForEach(DietaryPreference.allCases.filter({ $0 != .unknown }), id: \.self) { preference in
                        Toggle(isOn: Binding(
                            get: { preferences.isDietaryPreferenceSelected(preference) },
                            set: { _ in preferences.toggleDietaryPreference(preference) }
                        )) {
                            HStack {
                                imageFor(preference)
                                    .resizable()
                                    .frame(width: 20, height: 20)
                                Text(preference.rawValue.capitalized)
                            }
                        }
                    }
                }
            }
            
            Section("Favorite Dishes") {
                ForEach(preferences.favoriteDishes.sorted(), id: \.self) { dish in
                    Text(dish)
                }
                .onDelete { indexSet in
                    let dishesArray = Array(preferences.favoriteDishes).sorted()
                    for index in indexSet {
                        let dishToRemove = dishesArray[index]
                        preferences.favoriteDishes.remove(dishToRemove)
                    }
                }
                
                HStack {
                    TextField("Add Favorite Dish", text: $newKeyword)
                    Button(action: {
                        let trimmedDish = newKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmedDish.isEmpty else { return }
                        preferences.favoriteDishes.insert(trimmedDish)
                        newKeyword = ""
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.blue)
                    }
                }
            }
            
            Section("Excluded Keywords") {
                ForEach(preferences.excludedKeywords.sorted(), id: \.self) { keyword in
                    Text(keyword)
                }
                .onDelete { indexSet in
                    let keywordsArray = Array(preferences.excludedKeywords).sorted()
                    for index in indexSet {
                        let keywordToRemove = keywordsArray[index]
                        preferences.excludedKeywords.remove(keywordToRemove)
                    }
                }
                
                HStack {
                    TextField("Add Keyword", text: $newKeyword)
                    Button(action: {
                        let trimmedKeyword = newKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmedKeyword.isEmpty else { return }
                        preferences.excludedKeywords.insert(trimmedKeyword)
                        newKeyword = ""
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.blue)
                    }
                }
            }
        }
    }
}

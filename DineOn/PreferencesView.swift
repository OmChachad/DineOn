//
//  PreferencesView.swift
//  DineOn
//
//  Created by Om Chachad on 10/17/25.
//

import SwiftUI

struct PreferencesView: View {
    @StateObject private var preferences = Preferences.shared

    var body: some View {
        Form {
            Section("Allergens") {
                ForEach(Allergen.allCases.filter({ $0 != .notAnalyzed && $0 != .unknown }), id: \.self) { allergen in
                    Toggle(isOn: Binding(
                        get: { preferences.isAllergenSelected(allergen) },
                        set: { _ in preferences.toggleAllergen(allergen) }
                    )) {
                        HStack {
                            imageFor(allergen)
                                .resizable()
                                .frame(width: 20, height: 20)
                            Text(allergen.rawValue)
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
                                Text(preference.rawValue)
                            }
                        }
                    }
                }
            }
        }
    }
}

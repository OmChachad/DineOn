//
//  MenuNodeView.swift
//  DineOn
//
//  Created by Om Chachad on 10/17/25.
//

import SwiftUI

struct MenuNodeView: View {
    @StateObject private var preferences = Preferences.shared
    
    let node: MenuNode
    
    var body: some View {
        switch node.type {
        case .item:
            if itemFitsPreferences(node) {
                MenuItemView(node: node)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .header, .timeHeader:
            IndentedDisclosureGroup(expandedByDefault: true) {
                if let items = node.items {
                        ForEach(items, id: \.name) { item in
                            MenuNodeView(node: item)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } label: {
                Text(node.name)
                    .font(node.type == .timeHeader ? .headline : .title3)
                    .bold()
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
            }
        }
    }
    
    func itemFitsPreferences(_ node: MenuNode) -> Bool {
        // Allergens: reject if the food contains any selected allergen
        guard node.allergens?.contains(.notAnalyzed) == false else {
            return true
        }
        
        for keyword in preferences.excludedKeywords {
            if node.name.lowercased().contains(keyword.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)) {
                return false
            }
        }
        
        let selectedAllergens = preferences.selectedAllergens.compactMap { Allergen(rawValue: $0) }
        
        if (node.allergens ?? []).contains(where: { selectedAllergens.contains($0) }) {
            return false
        }
        
        // Dietary preferences: only check if user has enabled dietary restrictions
        if preferences.hasDietaryRestrictions {
            let selectedPreferences = preferences.selectedDietaryPreferences.compactMap { DietaryPreference(rawValue: $0) }
            let nodePreferences = node.preferences ?? []
            // Food must meet *all* selected dietary preferences
            for pref in selectedPreferences {
                switch pref {
                case .vegetarian:
                    return nodePreferences.contains(.vegetarian) || nodePreferences.contains(.vegan)
                case .vegan:
                    return nodePreferences.contains(.vegan)
                default:
                    return nodePreferences.contains(pref)
                }
            }
        }
        
        return true
    }
}

struct MenuItemView: View {
    let node: MenuNode
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(node.name)
                .font(.body)
            
            HStack(spacing: 5) {
                if let prefs = node.preferences, !prefs.isEmpty {
                    ForEach(prefs, id: \.self) { pref in
                        imageFor(pref)
                            .resizable()
                            .frame(width: 20, height: 20)
                    }
                }
                
                if let allergens = node.allergens, !allergens.isEmpty {
                    ForEach(allergens, id: \.self) { allergen in
                        imageFor(allergen)
                            .resizable()
                            .frame(width: 20, height: 20)
                    }
                }
            }
            
            if let disclaimers = node.disclaimers, !disclaimers.isEmpty {
                ForEach(disclaimers, id: \.self) { disclaimer in
                    Text(disclaimer)
                        .font(.caption2)
                        .foregroundColor(.yellow)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

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
    let chosenDate: String
    
    var body: some View {
        Group {
            switch node.type {
            case .item:
                if itemFitsPreferences(node) {
                    MenuItemView(node: node, chosenDate: chosenDate)
                }
            case .info:
                MenuInfoView(node: node, chosenDate: chosenDate)
            case .header, .timeHeader:
                if let items = node.items, !items.isEmpty {
                    IndentedDisclosureGroup(expandedByDefault: true) {
                        ForEach(items, id: \.name) { item in
                            MenuNodeView(node: item, chosenDate: chosenDate)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } label: {
                        MenuHeaderLabel(node: node, chosenDate: chosenDate)
                    }
                } else {
                    MenuHeaderLabel(node: node, chosenDate: chosenDate)
                }
            }
        }
        
            .environmentObject(preferences)
    }
    
    func itemFitsPreferences(_ node: MenuNode) -> Bool {
        // Allergens: reject if the food contains any selected allergen
        for keyword in preferences.excludedKeywords {
            if node.name.lowercased().contains(keyword.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)) {
                return false
            }
        }
        
        guard node.allergens?.contains(.notAnalyzed) == false else {
            return true
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

struct MenuHeaderLabel: View {
    let node: MenuNode
    let chosenDate: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(node.name)
                .font(node.type == .timeHeader ? .headline : .title3)
                .bold()
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)

            if let timingText = timingDisplayText(for: node, chosenDate: chosenDate) {
                Text(timingText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MenuItemView: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var preferences = Preferences.shared
    let node: MenuNode
    let chosenDate: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Group {
                Text(node.name)
            }
            
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

//            if let timingText = timingDisplayText(for: node, chosenDate: chosenDate) {
//                Text(timingText)
//                    .font(.subheadline)
//                    .foregroundStyle(.secondary)
//            }
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .contextMenu {
            Button(action: {
                if preferences.favoriteDishes.contains(node.name) {
                    preferences.favoriteDishes.remove(node.name)
                } else {
                    preferences.favoriteDishes.insert(node.name)
                }
            }) {
                Text(preferences.favoriteDishes.contains(node.name) ? "Remove from Favorites" : "Add to Favorites")
                Image(systemName: preferences.favoriteDishes.contains(node.name) ? "star.fill" : "star")
            }
            
            
                // Add to excluded keywords
                Button(action: {
                    preferences.excludedKeywords.insert(node.name)
                }) {
                    Text("Don't show this again.")
                    Image(systemName: "hand.thumbsdown.fill")
                }
        } preview: {
            MenuItemView(node: node, chosenDate: chosenDate)
                .lineLimit(3)
                .padding(10)
                .padding(.trailing, 100)
                .background(Color(UIColor.systemBackground))
                .cornerRadius(5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, preferences.favoriteDishes.contains(node.name) ? -10 : 0)
        }
        .padding(.vertical, preferences.favoriteDishes.contains(node.name) ? 10 : 0)
        .background {
            if preferences.favoriteDishes.contains(node.name) {
                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .frame(width: 3.5)
                        .foregroundStyle(.pink)
                        .padding(.leading)
                    
                    LinearGradient(colors: [Color.pink.opacity(colorScheme == .dark ? 0.3 : 0.2), Color.clear, Color.clear, Color.clear], startPoint: .leading, endPoint: .trailing)
                        .frame(maxWidth: 500)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.leading, -30)
                .ignoresSafeArea()

            }
        }
    }
}

struct MenuInfoView: View {
    let node: MenuNode
    let chosenDate: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if !node.name.isEmpty {
                Text(node.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
            }

            if let timingText = timingDisplayText(for: node, chosenDate: chosenDate) {
                Text(timingText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

func timingDisplayText(for node: MenuNode, chosenDate: String) -> String? {
    guard let timingInfo = node.timingInfo else { return nil }
    return timingDisplayText(for: timingInfo, chosenDate: chosenDate)
}

func timingDisplayText(for timingInfo: MenuTimingInfo, chosenDate: String) -> String {
    let fallback = absoluteTimingText(for: timingInfo)
    guard chosenDate == DiningFetcher.formatDate(Date()),
          let targetDate = dateForChosenDay(timeText: timingInfo.timeText, chosenDate: chosenDate) else {
        return fallback
    }

    let now = Date()
    switch timingInfo.kind {
    case .opensAt, .availableAt, .availableFrom, .servedAt:
        return targetDate > now ? "Opens \(relativeText(to: targetDate, from: now))" : "Open now"
    case .availableUntil:
        return targetDate > now ? "Available for \(relativeText(since: now, now: targetDate))" : "Closed \(relativeText(since: targetDate, now: now))"
    }
}

func absoluteTimingText(for timingInfo: MenuTimingInfo) -> String {
    switch timingInfo.kind {
    case .opensAt, .availableAt, .availableFrom, .servedAt:
        return "Opens at \(timingInfo.timeText)"
    case .availableUntil:
        return "Available until \(timingInfo.timeText)"
    }
}

func dateForChosenDay(timeText: String, chosenDate: String) -> Date? {
    let dateFormatter = DateFormatter()
    dateFormatter.locale = Locale(identifier: "en_US_POSIX")
    dateFormatter.dateFormat = "yyyy-MM-dd h:mma"

    let normalizedTime = timeText
        .replacingOccurrences(of: " ", with: "")
        .uppercased()

    return dateFormatter.date(from: "\(chosenDate) \(normalizedTime)")
}

func relativeText(to futureDate: Date, from now: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .full
    return formatter.localizedString(for: futureDate, relativeTo: now)
}

func relativeText(since earlierDate: Date, now: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .full
    return formatter.localizedString(for: earlierDate, relativeTo: now)
}

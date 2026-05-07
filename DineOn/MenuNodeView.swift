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

    private var visibilityPreferences: MenuVisibilityPreferences {
        MenuVisibilityPreferences(preferences: preferences)
    }
    
    var body: some View {
        Group {
            switch node.type {
            case .item:
                if shouldDisplayNode(node, preferences: visibilityPreferences)
                    && itemFitsPreferences(node, preferences: visibilityPreferences) {
                    MenuItemView(node: node, chosenDate: chosenDate)
                }
            case .info:
                if shouldDisplayNode(node, preferences: visibilityPreferences) {
                    MenuInfoView(node: node, chosenDate: chosenDate)
                }
            case .header, .timeHeader:
                if shouldDisplayNode(node, preferences: visibilityPreferences), let items = node.items, !items.isEmpty {
                    IndentedDisclosureGroup(expandedByDefault: true) {
                        ForEach(items, id: \.name) { item in
                            MenuNodeView(node: item, chosenDate: chosenDate)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } label: {
                        MenuHeaderLabel(node: node, chosenDate: chosenDate)
                    }
                } else if shouldDisplayNode(node, preferences: visibilityPreferences) {
                    MenuHeaderLabel(node: node, chosenDate: chosenDate)
                }
            }
        }
        
            .environmentObject(preferences)
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
    @StateObject private var suggestionsRepository = SuggestionsRepository.shared
    let node: MenuNode
    let chosenDate: String

    private var isFavorite: Bool {
        preferences.favoriteDishes.contains(node.name)
    }

    private var isSuggested: Bool {
        suggestionsRepository.isSuggestedItem(node.name, for: chosenDate)
    }

    private var shouldHighlight: Bool {
        isFavorite || isSuggested
    }
    
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
                if isFavorite {
                    preferences.favoriteDishes.remove(node.name)
                } else {
                    preferences.favoriteDishes.insert(node.name)
                }
            }) {
                Text(isFavorite ? "Remove from Favorites" : "Add to Favorites")
                Image(systemName: isFavorite ? "star.fill" : "star")
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
                .padding(.vertical, shouldHighlight ? -10 : 0)
        }
        .padding(.vertical, shouldHighlight ? 10 : 0)
        .background {
            ZStack {
                if isSuggested {
                    menuItemHighlight(color: .purple, leadingInset: 0)
                }

                if isFavorite {
                    menuItemHighlight(color: .pink, leadingInset: isSuggested ? 5.5 : 0)
                }
            }
        }
    }

    @ViewBuilder
    private func menuItemHighlight(color: Color, leadingInset: CGFloat) -> some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .frame(width: 3.5)
                .foregroundStyle(color)
                .padding(.leading)

            LinearGradient(
                colors: [color.opacity(colorScheme == .dark ? 0.3 : 0.2), Color.clear, Color.clear, Color.clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(maxWidth: 500)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, -30 + leadingInset)
        .ignoresSafeArea()
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

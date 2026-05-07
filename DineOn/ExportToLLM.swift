//
//  ExportToLLM.swift
//  DineOn
//
//  Created by Om Chachad on 10/12/25.
//

import Foundation

extension DiningMenu {
    /// Creates an LLM-friendly text export of all venues/meals/stations for a given date.
    func exportForLLM(date: String) -> String {
        guard data[date] != nil else {
            return "No dining data available for \(date)."
        }
        
        var output = "Dining Menus for \(date)\n\n"
        
        /// Sorted venue names
        let venueNames = venues(for: date).sorted()
        
        for venue in venueNames {
            output += "==============================\n"
            output += "🏫 Venue: \(venue)\n"
            output += "==============================\n\n"
            
            let mealNames = meals(for: date, venue: venue)
            
            /// Sort meals by `mealOrder` if possible
            let sortedMeals = mealNames.sorted {
                let a = mealOrder[$0] ?? Int.max
                let b = mealOrder[$1] ?? Int.max
                return a < b
            }
            
            for meal in sortedMeals {
                output += "🍽️ Meal: \(meal)\n\n"
                
                let stationNames = stations(for: date, venue: venue, meal: meal).sorted()
                
                for station in stationNames {
                    output += "— Station: \(station)\n"
                    
                    guard let stationNodes = nodes(for: date, venue: venue, meal: meal, station: station) else {
                        output += "  (No items)\n\n"
                        continue
                    }
                    
                    for node in stationNodes {
                        let formatted = formatNode(node, indent: "  ")
                        output += formatted + "\n"
                    }
                    
                    output += "\n"
                }
                
                output += "\n"
            }
        }
        
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func exportSuggestionsForLLM(date: String, preferences: MenuVisibilityPreferences) -> String {
        guard data[date] != nil else {
            return "No dining data available for \(date)."
        }

        var output = "DATE \(date)\n"
        let venueNames = venues(for: date).sorted()
        var includedVenueCount = 0

        for venue in venueNames {
            let mealNames = prioritizedMealNames(from: meals(for: date, venue: venue), chosenDate: date)
            var venueOutput = ""

            for meal in mealNames {
                let stationNames = stations(for: date, venue: venue, meal: meal).sorted()
                var mealOutput = ""

                for station in stationNames {
                    guard preferences.hasAAZAccess || !isAAZStation(station) else {
                        continue
                    }

                    guard let stationNodes = nodes(for: date, venue: venue, meal: meal, station: station) else {
                        continue
                    }

                    let visibleLines = suggestionLines(from: stationNodes, indent: "  ", preferences: preferences)
                    guard !visibleLines.isEmpty else {
                        continue
                    }

                    mealOutput += "STATION \(displayStationName(station, hasAAZAccess: preferences.hasAAZAccess))\n"
                    mealOutput += visibleLines.joined(separator: "\n")
                    mealOutput += "\n"
                }

                guard !mealOutput.isEmpty else {
                    continue
                }

                venueOutput += "MEAL \(meal)\n"
                venueOutput += mealOutput
            }

            guard !venueOutput.isEmpty else {
                continue
            }

            includedVenueCount += 1
            output += "VENUE \(venue)\n"
            output += venueOutput
        }

        guard includedVenueCount > 0 else {
            return "No visible dining suggestions are available for \(date)."
        }

        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func suggestionMealSlots(for date: String, preferences: MenuVisibilityPreferences) -> [String] {
        guard data[date] != nil else {
            return []
        }

        var visibleMealsSet: Set<String> = []
        for venue in venues(for: date) {
            let mealsForVenue = prioritizedMealNames(from: meals(for: date, venue: venue), chosenDate: date)
            for meal in mealsForVenue {
                let hasVisibleItems = stations(for: date, venue: venue, meal: meal)
                    .filter { preferences.hasAAZAccess || !isAAZStation($0) }
                    .contains { station in
                        guard let stationNodes = nodes(for: date, venue: venue, meal: meal, station: station) else {
                            return false
                        }
                        return !suggestionLines(from: stationNodes, indent: "  ", preferences: preferences).isEmpty
                    }
                if hasVisibleItems {
                    visibleMealsSet.insert(meal)
                }
            }
        }

        return prioritizedMealNames(from: Array(visibleMealsSet), chosenDate: date)
    }
    
    // MARK: - Helpers
    
    private func formatNode(_ node: MenuNode, indent: String) -> String {
        switch node.type {
        case .header:
            var line = "\(indent)📌 \(node.name.uppercased())"
            if let timingInfo = node.timingInfo {
                line += "\n\(indent)   ⓘ \(timingText(for: timingInfo))"
            }
            return line
            
        case .timeHeader:
            return "\(indent)⏱️ \(node.name)"
            
        case .item:
            var line = "\(indent)• \(node.name)"
            
            // Add preferences like (vegan, vegetarian, etc.)
            if let prefs = node.preferences, !prefs.isEmpty {
                let prefList = prefs.map { $0.rawValue }.joined(separator: ", ")
                line += "  [\(prefList)]"
            }
            
            // Add allergens like {dairy, soy}
            if let allergens = node.allergens, !allergens.isEmpty {
                let allergenList = allergens.map { $0.rawValue }.joined(separator: ", ")
                line += "  {Allergens: \(allergenList)}"
            }
            
            // Add disclaimers
            if let disclaimers = node.disclaimers, !disclaimers.isEmpty {
                for d in disclaimers {
                    line += "\n\(indent)   - \(d)"
                }
            }
            
            return line
        case .info:
            if node.name.isEmpty, let timingInfo = node.timingInfo {
                return "\(indent)ⓘ \(timingText(for: timingInfo))"
            }

            if let timingInfo = node.timingInfo {
                return "\(indent)ⓘ \(node.name) (\(timingText(for: timingInfo)))"
            }

            return "\(indent)ⓘ \(node.name)"
        }
    }

    private func timingText(for timingInfo: MenuTimingInfo) -> String {
        switch timingInfo.kind {
        case .opensAt, .availableAt, .availableFrom, .servedAt:
            return "Opens at \(timingInfo.timeText)"
        case .availableUntil:
            return "Available until \(timingInfo.timeText)"
        }
    }

    private func suggestionLines(
        from nodes: [MenuNode],
        indent: String,
        preferences: MenuVisibilityPreferences
    ) -> [String] {
        var lines: [String] = []

        for node in nodes {
            guard shouldDisplayNode(node, preferences: preferences) else {
                continue
            }

            switch node.type {
            case .item:
                guard itemFitsPreferences(node, preferences: preferences) else {
                    continue
                }
                lines.append(formattedSuggestionItem(node, indent: indent, preferences: preferences))
            case .header, .timeHeader:
                let childLines = suggestionLines(
                    from: node.items ?? [],
                    indent: "\(indent)  ",
                    preferences: preferences
                )
                guard !childLines.isEmpty else {
                    continue
                }
                lines.append("\(indent)SECTION \(node.name)")
                lines.append(contentsOf: childLines)
            case .info:
                continue
            }
        }

        return lines
    }

    private func formattedSuggestionItem(
        _ node: MenuNode,
        indent: String,
        preferences: MenuVisibilityPreferences
    ) -> String {
        var components = ["\(indent)ITEM \(node.name)"]

        if preferences.isFavorite(node.name) {
            components.append("fav")
        }

        if let prefs = node.preferences, !prefs.isEmpty {
            let prefList = prefs.map(\.rawValue).joined(separator: ", ")
            components.append("pref=\(prefList)")
        }

        if let allergens = node.allergens, !allergens.isEmpty {
            let allergenList = allergens.map(\.rawValue).joined(separator: ", ")
            components.append("allergen=\(allergenList)")
        }

        if let disclaimers = node.disclaimers, !disclaimers.isEmpty {
            let disclaimerList = disclaimers.joined(separator: "; ")
            components.append("note=\(disclaimerList)")
        }

        return components.joined(separator: " | ")
    }
}

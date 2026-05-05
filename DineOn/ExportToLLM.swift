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
}

//
//  MealView.swift
//  DineOn
//
//  Created by Om Chachad on 10/17/25.
//

import SwiftUI

struct MealView: View {
    var meal: MealName
    var venueName: VenueName
    var chosenDate: String
    
    func expiredMeals() -> [String] {
        guard chosenDate == {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.string(from: Date.now)
        }() else { return [] }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH"
        
        let hourOfDay = Int(dateFormatter.string(from: Date.now))
        
        guard let hourOfDay else { return [] }
        
        switch (hourOfDay) {
        case 1...10:
            return []
        case 11...16:
            return ["Breakfast"]
        case 17...24:
            return ["Breakfast", "Lunch", "Brunch"]
        default:
            return []
        }
    }

    var isExpired: Bool {
        expiredMeals().contains(meal)
    }
    
    @ViewBuilder
    var body: some View {
        if !isExpired {
            IndentedDisclosureGroup(expandedByDefault: expiredMeals().contains(meal) == false) {
                ForEach(DiningFetcher.shared.diningMenu!.stations(for: chosenDate, venue: venueName, meal: meal), id: \.self) { station in
                    IndentedDisclosureGroup(expandedByDefault: true) {
                        DiningFetcher.shared.diningMenu!.nodes(for: chosenDate, venue: venueName, meal: meal, station: station).map { nodes in
                            ForEach(nodes, id: \.self) { node in
                                MenuNodeView(node: node)
                            }
                        }
                    } label: {
                        Text(station)
                            .font(.title2)
                            .bold()
                            .foregroundColor(.primary)
                    }
                }
            } label: {
                Group {
                    if isExpired {
                        Text("~~\(meal)~~")
                    } else {
                        Text(meal)
                    }
                }
                
                .font(.title)
                .bold()
                .foregroundColor(.primary)
                .fontWidth(.expanded)
            }
            
            
            
            Divider()
                .bold()
        }
    }
}

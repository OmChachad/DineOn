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

    private var stations: [String] {
        DiningFetcher.shared.menuData[chosenDate]?[venueName]?[meal]?.keys.sorted() ?? []
    }

    func expiredMeals() -> [String] {
        guard chosenDate == DiningFetcher.formatDate(Date()) else { return [] }

        let hour = Calendar.current.component(.hour, from: Date.now)
        switch hour {
        case 1...10:  return []
        case 11...16: return ["Breakfast"]
        case 17...24: return ["Breakfast", "Lunch", "Brunch"]
        default:      return []
        }
    }

    var isExpired: Bool { expiredMeals().contains(meal) }

    @ViewBuilder
    var body: some View {
        if !isExpired {
            IndentedDisclosureGroup(expandedByDefault: true) {
                ForEach(stations, id: \.self) { station in
                    IndentedDisclosureGroup(expandedByDefault: true) {
                        if let nodes = DiningFetcher.shared.menuData[chosenDate]?[venueName]?[meal]?[station] {
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
                Text(meal)
                    .font(.title)
                    .bold()
                    .foregroundColor(.primary)
                    .fontWidth(.expanded)
            }

            Divider().bold()
        }
    }
}

//
//  MealView.swift
//  DineOn
//
//  Created by Om Chachad on 10/17/25.
//

import SwiftUI

struct MealView: View {
    @ObservedObject private var fetcher = DiningFetcher.shared

    var meal: MealName
    var venueName: VenueName
    var chosenDate: String

    private var stations: [String] {
        fetcher.menuData[chosenDate]?[venueName]?[meal]?.keys.sorted() ?? []
    }

    func expiredMeals() -> [String] {
        Array(expiredMealNames(for: chosenDate))
    }

    var isExpired: Bool { expiredMeals().contains(meal) }

    @ViewBuilder
    var body: some View {
        if !isExpired {
            IndentedDisclosureGroup(expandedByDefault: true) {
                ForEach(stations, id: \.self) { station in
                    let stationNodes = fetcher.menuData[chosenDate]?[venueName]?[meal]?[station] ?? []
                    let stationTimingNode = stationNodes.first(where: isStationTimingNode)
                    let stationWarningNode = stationNodes.first(where: isStationWarningNode)
                    let visibleNodes = stationNodes.filter { $0 != stationTimingNode && $0 != stationWarningNode }

                    IndentedDisclosureGroup(expandedByDefault: true) {
                        ForEach(visibleNodes, id: \.self) { node in
                            MenuNodeView(node: node, chosenDate: chosenDate)
                        }
                    } label: {
                        StationHeaderLabel(
                            title: station,
                            warningText: stationWarningNode.map(stationWarningDisplayText),
                            timingText: stationTimingNode.flatMap { timingDisplayText(for: $0, chosenDate: chosenDate) }
                        )
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

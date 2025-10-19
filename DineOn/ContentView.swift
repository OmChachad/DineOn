//
//  ContentView.swift
//  DineOn
//
//  Created by Om Chachad on 10/17/25.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var diningFetcher = DiningFetcher.shared
    
    
    @State private var chosenDate: String = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }()
    
    var todaysDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
    
    
    var body: some View {
        Group {
            if diningFetcher.isLoading {
                ProgressView("Fetching Dining Menu...")
            } else if let menu = diningFetcher.diningMenu {
                
                NavigationStack {
                    TabView {
                        ForEach(menu.venues(for: chosenDate).sorted(), id: \.self) { venueName in
                            Tab(betterVenueName(for: venueName), systemImage: betterVenueIcon(for: venueName)) {
                                
                                ScrollView {
                                    LazyVStack(pinnedViews: [.sectionHeaders]) {
                                        ForEach(menu.meals(for: chosenDate, venue: venueName).sorted { meal1, meal2 in
                                            return mealOrder[meal1] ?? 99 < mealOrder[meal2] ?? 99
                                        }, id: \.self) { meal in
                                            MealView(meal: meal, venueName: venueName, chosenDate: chosenDate)
                                        }
                                        .padding()
                                    }
                                    .safeAreaPadding(.top, 40)
                                    .contentMargins(.top, 30, for: .scrollIndicators)
                                }
                            }
                        }
                        
                        
                        Tab(role: .search) {
                            PreferencesView()
                        } label: {
                            Label("Settings", systemImage: "gear")
                        }
                    }
                    
                    .safeAreaInset(edge: .top) {
                        HStack {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack {
                                    ForEach(menu.availableDates.sorted().filter( { $0 >= todaysDate } ), id: \.self) { dateString in
                                        Button(action: {
                                            chosenDate = dateString
                                        }) {
                                            Text(stringToDate(for: dateString)!.formatted(date: .abbreviated, time: .omitted))
                                                .padding(8)
                                                .foregroundColor(chosenDate == dateString ? .white : .primary)
                                                .bold(chosenDate == dateString)
                                                .glassEffect(.regular.tint(chosenDate == dateString ?  .blue : nil), in: .capsule)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .scrollClipDisabled()
                            .ignoresSafeArea(.all, edges: .horizontal)
                        }
                        .padding(.horizontal)
                    }
                    .navigationTitle("DineOn")
                    .navigationBarTitleDisplayMode(.inline)
                }
            } else {
                Text("No dining menu available.")
            }
        }
        .task {
            DiningFetcher.shared.fetchDiningMenu()
        }
    }
    
    func betterVenueName(for venue: String) -> String {
        switch venue {
        case "Everybody's Kitchen":
            return "EVK"
        case "Parkside Residential":
            return "Parkside"
        case "USC Village":
            return "Village"
        default:
            return venue
        }
    }
    
    func betterVenueIcon(for venue: String) -> String {
        switch venue {
        case "Everybody's Kitchen":
            return "person.3.fill"
        case "Parkside Residential":
            return "fork.knife"
        case "USC Village":
            return "building.columns.fill"
        default:
            return "fork.knife"
        }
    }
    
    func stringToDate(for string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: string)
    }
}

#Preview {
    ContentView()
}

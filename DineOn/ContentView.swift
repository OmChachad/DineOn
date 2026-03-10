//
//  ContentView.swift
//  DineOn
//
//  Created by Om Chachad on 10/17/25.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var diningFetcher = DiningFetcher.shared
    @ObservedObject var preferences = Preferences.shared
    
    
    @State private var chosenDate: String = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }()
    
    @State private var chosenMeal: String? = nil
    
    var todaysDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
    
    /// Returns the most appropriate current meal based on time of day (uses same thresholds as MealView).
    var currentMealForTimeOfDay: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0...10:
            return "Breakfast"
        case 11...16:
            return "Lunch"
        default:
            return "Dinner"
        }
    }
    
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    
    /// Returns the effective chosen meal, falling back to the best match for the current time.
    func effectiveMeal(for availableMeals: [String]) -> String {
        if let chosen = chosenMeal, availableMeals.contains(chosen) {
            return chosen
        }
        let preferred = currentMealForTimeOfDay
        if availableMeals.contains(preferred) {
            return preferred
        }
        // Brunch can substitute for Breakfast/Lunch
        if (preferred == "Breakfast" || preferred == "Lunch"), availableMeals.contains("Brunch") {
            return "Brunch"
        }
        return availableMeals.sorted { (mealOrder[$0] ?? 99) < (mealOrder[$1] ?? 99) }.first ?? preferred
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
                                let availableMeals = menu.meals(for: chosenDate, venue: venueName).sorted {
                                    (mealOrder[$0] ?? 99) < (mealOrder[$1] ?? 99)
                                }
                                let activeMeal = effectiveMeal(for: availableMeals)
                                
                                ScrollView {
                                    LazyVStack(pinnedViews: [.sectionHeaders]) {
                                        MealContentView(meal: activeMeal, venueName: venueName, chosenDate: chosenDate)
                                            .padding()
                                    }
                                    .contentMargins(.top, 30, for: .scrollIndicators)
                                }
                                .refreshable {
                                    await diningFetcher.refreshMenu(for: chosenDate)
                                }
                                .safeAreaBar(edge: .top) {
                                    VStack(spacing: 6) {
                                        dateSelector(menu: menu)
                                        activeFiltersBar()
                                    }
                                    .padding(.horizontal, 20)
                                }
                                .safeAreaBar(edge: .bottom) {
                                    mealSelector(availableMeals: availableMeals, activeMeal: activeMeal)
                                        .padding(20)
                                }
                            }
                        }
                        
                        Tab(role: .search) {
                            PreferencesView()
                        } label: {
                            Label("Settings", systemImage: "gear")
                        }
                    }
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            ShareLink(item: menu.exportForLLM(date: chosenDate)) {
                                Label("Export to LLM", systemImage: "square.and.arrow.up")
                            }
                        }
                    }
                    .navigationTitle("DineOn")
                    .navigationBarTitleDisplayMode(.inline)
                }
                
                .environment(\.horizontalSizeClass, .compact)
            } else {
                Text("No dining menu available.")
            }
        }
        .task {
            DiningFetcher.shared.fetchDiningMenu()
        }
        .onChange(of: chosenDate) { _, _ in
            chosenMeal = nil
        }
    }
    
    // MARK: - Selector Views
    
    @ViewBuilder
    func dateSelector(menu: DiningMenu) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(menu.availableDates.sorted().filter( { $0 >= todaysDate } ), id: \.self) { dateString in
                    Button(action: {
                        chosenDate = dateString
                    }) {
                        Group {
                            if dateString == todaysDate {
                                Text("Today")
                            } else {
                                Text(stringToDate(for: dateString)!.formatted(.dateTime.month().day()))
                            }
                        }
                            .padding(8)
                            .foregroundColor(chosenDate == dateString ? .white : .primary)
                            .bold(chosenDate == dateString)
                            .glassEffect(.regular.tint(chosenDate == dateString ?  .accentColor : nil), in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .scrollTargetLayout()
                }
            }
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollClipDisabled()
        .ignoresSafeArea(.all, edges: .horizontal)
    }
    
    @ViewBuilder
    func activeFiltersBar() -> some View {
        let activeAllergens = Allergen.allCases.filter {
            $0 != .notAnalyzed && $0 != .unknown && preferences.isAllergenSelected($0)
        }
        let activeDietaryPrefs = DietaryPreference.allCases.filter {
            $0 != .unknown && preferences.hasDietaryRestrictions && preferences.isDietaryPreferenceSelected($0)
        }
        
        let hasActiveFilters = !activeAllergens.isEmpty || !activeDietaryPrefs.isEmpty
        
        if hasActiveFilters {
            HStack(spacing: 10) {
                ForEach(activeAllergens, id: \.self) { allergen in
                    HStack(spacing: 4) {
                        imageFor(allergen)
                            .resizable()
                            .frame(width: 14, height: 14)
                        Text(allergen.rawValue.replacingOccurrences(of: "-", with: " ").capitalized)
                            .font(.caption2)
                    }
                }
                
                ForEach(activeDietaryPrefs, id: \.self) { pref in
                    HStack(spacing: 4) {
                        imageFor(pref)
                            .resizable()
                            .frame(width: 14, height: 14)
                        Text(pref.rawValue.replacingOccurrences(of: "-", with: " ").capitalized)
                            .font(.caption2)
                    }
                }
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 5)
        }
    }
    
    @ViewBuilder
    func mealSelector(availableMeals: [String], activeMeal: String) -> some View {
            HStack {
                ForEach(availableMeals, id: \.self) { meal in
                    Button(action: {
                        chosenMeal = meal
                    }) {
                        Text(meal)
                            .padding(8)
                            .foregroundColor(activeMeal == meal ? .white : .primary)
                            .bold(activeMeal == meal)
                            .frame(maxWidth: .infinity)
                            .glassEffect(.regular.tint(activeMeal == meal ? .accentColor : nil).interactive(), in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .scrollTargetLayout()
                }
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollClipDisabled()
        .ignoresSafeArea(.all, edges: .horizontal)
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

/// Shows the stations and items for a single meal at a venue (replaces the old MealView loop).
struct MealContentView: View {
    var meal: MealName
    var venueName: VenueName
    var chosenDate: String
    
    var body: some View {
        ForEach(DiningFetcher.shared.diningMenu?.stations(for: chosenDate, venue: venueName, meal: meal) ?? [], id: \.self) { station in
            IndentedDisclosureGroup(expandedByDefault: true) {
                DiningFetcher.shared.diningMenu?.nodes(for: chosenDate, venue: venueName, meal: meal, station: station).map { nodes in
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
    }
}

#Preview {
    ContentView()
}

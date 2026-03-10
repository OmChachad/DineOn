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
    @ObservedObject var locationManager = LocationManager.shared

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

    /// Returns the most appropriate current meal based on time of day.
    var currentMealForTimeOfDay: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0...10: return "Breakfast"
        case 11...16: return "Lunch"
        default: return "Dinner"
        }
    }

    @Environment(\.horizontalSizeClass) var horizontalSizeClass

    func effectiveMeal(for availableMeals: [String]) -> String {
        if let chosen = chosenMeal, availableMeals.contains(chosen) { return chosen }
        let preferred = currentMealForTimeOfDay
        if availableMeals.contains(preferred) { return preferred }
        if (preferred == "Breakfast" || preferred == "Lunch"), availableMeals.contains("Brunch") { return "Brunch" }
        return availableMeals.sorted { (mealOrder[$0] ?? 99) < (mealOrder[$1] ?? 99) }.first ?? preferred
    }
    
    @State private var chosenTab: String = ""

    var body: some View {
        Group {
            if diningFetcher.isLoading {
                ProgressView("Fetching Dining Menu...")
            } else if let menu = diningFetcher.diningMenu {
                NavigationStack {
                    TabView(selection: $chosenTab) {
                        ForEach(sortedVenues(from: menu), id: \.self) { venueName in
                            let venue = DiningVenue(rawValue: venueName)
                            
                            Tab(venue?.shortName ?? venueName, systemImage: venue?.iconName ?? "fork.knife", value: venueName) {
                                let availableMeals = menu.meals(for: chosenDate, venue: venueName).sorted {
                                    (mealOrder[$0] ?? 99) < (mealOrder[$1] ?? 99)
                                }
                                let activeMeal = effectiveMeal(for: availableMeals)

                                Group {
                                    if availableMeals.isEmpty {
                                        ContentUnavailableView(
                                            "No Menu Available",
                                            systemImage: "fork.knife.circle",
                                            description: Text("No meals are being served at \(venue?.shortName ?? venueName) on this day.")
                                        )
                                    } else {
                                        ScrollView {
                                            LazyVStack(pinnedViews: [.sectionHeaders]) {
                                                MealContentView(meal: activeMeal, venueName: venueName, chosenDate: chosenDate)
                                                    .padding()
                                            }
//                                            .padding(.top, 50)
                                        }
                                        .contentMargins(.top, 50, for: .scrollIndicators)
                                        .contentMargins(.top, 50, for: .scrollContent)
                                    }
                                }
                                .refreshable {
                                    await diningFetcher.refreshMenu(for: chosenDate)
                                }
                                .safeAreaBar(edge: .bottom) {
                                    mealSelector(availableMeals: availableMeals, activeMeal: activeMeal)
                                        .padding(20)
                                }
                            }
                        }
                        

                        Tab(value: "Settings", role: .search) {
                            PreferencesView()
                        } label: {
                            Label("Settings", systemImage: "gear")
                        }
                    }
                    .safeAreaBar(edge: .top) {
                        Group {
                            if chosenTab != "Settings" {
                                VStack(spacing: 6) {
                                    dateSelector(menu: menu)
                                    activeFiltersBar()
                                }
                                .transition(.blurReplace)
                            }
                        }
                        .padding(.horizontal, 20)
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
            locationManager.requestLocationPermission()
        }
        .onChange(of: chosenDate) { _, _ in
            chosenMeal = nil
        }
        .animation(.default, value: chosenTab)
    }

    // MARK: - Selector Views

    @ViewBuilder
    func dateSelector(menu: DiningMenu) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(menu.availableDates.sorted().filter({ $0 >= todaysDate }), id: \.self) { dateString in
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
                        .glassEffect(.regular.tint(chosenDate == dateString ? .accentColor : nil), in: .capsule)
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
                        imageFor(allergen).resizable().frame(width: 14, height: 14)
                        Text(allergen.rawValue.replacingOccurrences(of: "-", with: " ").capitalized)
                            .font(.caption2)
                    }
                }
                ForEach(activeDietaryPrefs, id: \.self) { pref in
                    HStack(spacing: 4) {
                        imageFor(pref).resizable().frame(width: 14, height: 14)
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
            }
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollClipDisabled()
        .ignoresSafeArea(.all, edges: .horizontal)
    }

    func stringToDate(for string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: string)
    }

    func sortedVenues(from menu: DiningMenu) -> [String] {
        let venues = menu.venues(for: chosenDate)
        if let proximitySorted = locationManager.sortedVenuesByProximity(venues) { return proximitySorted }
        return venues.sorted()
    }
}

// MARK: - MealContentView

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
                    .multilineTextAlignment(.leading)
            }
        }
    }
}

#Preview {
    ContentView()
}

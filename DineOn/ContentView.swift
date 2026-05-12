//
//  ContentView.swift
//  DineOn
//
//  Created by Om Chachad on 10/17/25.
//

import SwiftUI
import SafariServices

struct ContentView: View {
    @ObservedObject var fetcher = DiningFetcher.shared
    @ObservedObject var preferences = Preferences.shared
    @ObservedObject var locationManager = LocationManager.shared

    @State private var chosenDate: String = DiningFetcher.formatDate(Date())
    @State private var chosenMeal: String? = nil
    @State private var chosenTab: String = ""
    @State private var feedbackURL: URL?
    @State private var isShowingFeedbackSheet = false

    @Environment(\.horizontalSizeClass) var horizontalSizeClass

    // MARK: - Date helpers

    private var todaysDate: String { DiningFetcher.formatDate(Date()) }

    /// 7-day window starting today.
    private var selectableDates: [String] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        return (0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: start)
                .map { DiningFetcher.formatDate($0) }
        }
    }

    private var fetchState: DateFetchState {
        fetcher.fetchStates[chosenDate] ?? .idle
    }

    // MARK: - Venue helpers

    /// All three venue tabs, sorted by proximity when near campus.
    private var sortedVenues: [DiningVenue] {
        let names = DiningVenue.allCases.map(\.rawValue)
        if let sorted = locationManager.sortedVenuesByProximity(names) {
            return sorted.compactMap { DiningVenue(rawValue: $0) }
        }
        return DiningVenue.allCases
    }

    private func availableMeals(for venueName: String) -> [String] {
        (fetcher.menuData[chosenDate]?[venueName]?.keys
            .sorted { (mealOrder[$0] ?? 99) < (mealOrder[$1] ?? 99) }) ?? []
    }

    private var selectedVenue: DiningVenue? {
        DiningVenue(rawValue: chosenTab)
    }

    // MARK: - Meal auto-selection

    private var currentMealForTimeOfDay: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 0...10: return "Breakfast"
        case 11...16: return "Lunch"
        default: return "Dinner"
        }
    }

    private func effectiveMeal(for meals: [String]) -> String {
        if let chosen = chosenMeal, meals.contains(chosen) { return chosen }
        let preferred = currentMealForTimeOfDay
        if meals.contains(preferred) { return preferred }
        if (preferred == "Breakfast" || preferred == "Lunch"), meals.contains("Brunch") { return "Brunch" }
        return meals.sorted { (mealOrder[$0] ?? 99) < (mealOrder[$1] ?? 99) }.first ?? preferred
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            TabView(selection: $chosenTab) {
                ForEach(sortedVenues, id: \.rawValue) { venue in
                    Tab(venue.shortName, systemImage: venue.iconName, value: venue.rawValue) {
                        venueTab(for: venue)
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
                            dateSelector()
                            activeFiltersBar()
                        }
                        .transition(.blurReplace)
                    }
                }
                .padding(.horizontal, 20)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        if let venue = selectedVenue {
                            feedbackURL = venue.feedbackURL
                            isShowingFeedbackSheet = true
                        }
                    } label: {
                        Image(systemName: "exclamationmark.bubble")
                    }
                    .accessibilityLabel("Open \(selectedVenue?.shortName ?? "") feedback form")
                }
            }
            .navigationTitle("DineOn")
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(isPresented: $isShowingFeedbackSheet, onDismiss: {
            feedbackURL = nil
        }) {
            if let feedbackURL {
                SafariSheet(url: feedbackURL)
            }
        }
        .environment(\.horizontalSizeClass, .compact)
        .task(id: chosenDate) {
            chosenMeal = nil
            fetcher.fetchMenu(for: chosenDate)
        }
        .task {
            locationManager.requestLocationPermission()
        }
        .animation(.default, value: chosenTab)
    }

    // MARK: - Venue Tab

    @ViewBuilder
    private func venueTab(for venue: DiningVenue) -> some View {
        let meals = availableMeals(for: venue.rawValue)
        let activeMeal = effectiveMeal(for: meals)

        Group {
            switch fetchState {
            case .loading where fetcher.menuData[chosenDate] == nil:
                ProgressView("Loading menu…")
            case .noMenu:
                ContentUnavailableView(
                    "No Menu Available",
                    systemImage: "fork.knife.circle",
                    description: Text("No menus were found for this date.")
                )
            case .error(let message):
                ContentUnavailableView(
                    "Couldn't Load Menu",
                    systemImage: "wifi.slash",
                    description: Text(message)
                )
            case .idle:
                ProgressView("Loading menu…")
            default:
                if meals.isEmpty {
                    ContentUnavailableView(
                        "No Menu Available",
                        systemImage: "fork.knife.circle",
                        description: Text("No meals are being served at \(venue.shortName) on this day.")
                    )
                } else {
                    ScrollView {
                        LazyVStack(pinnedViews: [.sectionHeaders]) {
                            MealContentView(meal: activeMeal, venueName: venue.rawValue, chosenDate: chosenDate)
                                .padding()
                        }
                    }
                    .contentMargins(.top, 50, for: .scrollIndicators)
                    .contentMargins(.top, 50, for: .scrollContent)
                }
            }
        }
        .refreshable {
            await fetcher.refresh(for: chosenDate)
        }
        .safeAreaBar(edge: .bottom) {
            if !meals.isEmpty {
                mealSelector(availableMeals: meals, activeMeal: activeMeal)
                    .padding(20)
            }
        }
    }

    // MARK: - Date Selector

    @ViewBuilder
    private func dateSelector() -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(selectableDates, id: \.self) { dateString in
                    Button {
                        chosenDate = dateString
                    } label: {
                        Group {
                            if dateString == todaysDate {
                                Text("Today")
                            } else if let date = dateFromString(dateString) {
                                Text(date.formatted(.dateTime.month().day()))
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

    // MARK: - Active Filters Bar
    @ViewBuilder
    private func activeFiltersBar() -> some View {
        let activeAllergens = Allergen.allCases.filter {
            $0 != .notAnalyzed && $0 != .unknown && preferences.isAllergenSelected($0)
        }
        let activeDietaryPrefs = DietaryPreference.allCases.filter {
            $0 != .unknown && preferences.hasDietaryRestrictions && preferences.isDietaryPreferenceSelected($0)
        }

        if !activeAllergens.isEmpty || !activeDietaryPrefs.isEmpty {
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

    // MARK: - Meal Selector

    @ViewBuilder
    private func mealSelector(availableMeals: [String], activeMeal: String) -> some View {
        let isCompactWidth = horizontalSizeClass == .compact

        HStack(spacing: isCompactWidth ? 8 : 10) {
            ForEach(availableMeals, id: \.self) { meal in
                Button {
                    chosenMeal = meal
                } label: {
                    Text(meal)
                        .padding(8)
                        .foregroundColor(activeMeal == meal ? .white : .primary)
                        .bold(activeMeal == meal)
                        .frame(maxWidth: isCompactWidth ? .infinity : nil)
                        .glassEffect(.regular.tint(activeMeal == meal ? .accentColor : nil).interactive(), in: .capsule)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .scrollTargetBehavior(.viewAligned)
        .scrollClipDisabled()
        .ignoresSafeArea(.all, edges: .horizontal)
    }

    // MARK: - Helpers

    private func dateFromString(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: string)
    }
}



// MARK: - MealContentView

struct MealContentView: View {
    @ObservedObject private var fetcher = DiningFetcher.shared
    @ObservedObject private var preferences = Preferences.shared

    var meal: MealName
    var venueName: VenueName
    var chosenDate: String

    var body: some View {
        ForEach(visibleStations, id: \.self) { station in
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
                    title: displayStationName(station, hasAAZAccess: preferences.hasAAZAccess),
                    warningText: stationWarningNode.map(stationWarningDisplayText),
                    timingText: stationTimingNode.flatMap { timingDisplayText(for: $0, chosenDate: chosenDate) }
                )
            }
        }
    }

    private var visibleStations: [String] {
        let stations = fetcher.menuData[chosenDate]?[venueName]?[meal]?.keys.sorted() ?? []
        guard venueName == DiningVenue.parkside.rawValue, !preferences.hasAAZAccess else {
            return stations
        }

        return stations.filter { !isAAZStation($0) }
    }
}

struct StationHeaderLabel: View {
    let title: String
    var warningText: String?
    var timingText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.title2)
                .bold()
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)

            if let warningText, !warningText.isEmpty {
                Text(warningText)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.yellow)
                    .multilineTextAlignment(.leading)
            }

            if let timingText {
                Text(timingText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

func isStationTimingNode(_ node: MenuNode) -> Bool {
    node.type == .info && node.name.isEmpty && node.timingInfo != nil
}

#Preview {
    ContentView()
}

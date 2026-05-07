//
//  SuggestionsViewModel.swift
//  DineOn
//
//  Created by Codex on 05/06/26.
//

import Foundation
import Combine

@MainActor
final class SuggestionsViewModel: ObservableObject {
    @Published private(set) var state: SuggestionsState = .idle
    @Published private(set) var response: MealSuggestionResponse?
    @Published private(set) var selectedDate: String = DiningFetcher.formatDate(.now)
    @Published private(set) var availableMealSlots: [String] = []
    @Published private(set) var consumedMeals: [ConsumedMealLogEntry] = []
    @Published private(set) var consumedCalories: Int = 0
    @Published private(set) var isRefreshing = false
    @Published private(set) var activeCaloriesLocal: Int?

    private let repository: SuggestionsRepository
    private let apiClient: SuggestionsAPIClient
    private let fetcher: DiningFetcher
    private let nutritionRepository: NutritionProfileRepository
    private let healthKitService: HealthKitNutritionService
    private let preferences: Preferences

    convenience init() {
        self.init(
            repository: .shared,
            apiClient: .shared,
            fetcher: .shared,
            nutritionRepository: .shared,
            healthKitService: .shared,
            preferences: .shared
        )
    }

    init(
        repository: SuggestionsRepository,
        apiClient: SuggestionsAPIClient,
        fetcher: DiningFetcher,
        nutritionRepository: NutritionProfileRepository,
        healthKitService: HealthKitNutritionService,
        preferences: Preferences
    ) {
        self.repository = repository
        self.apiClient = apiClient
        self.fetcher = fetcher
        self.nutritionRepository = nutritionRepository
        self.healthKitService = healthKitService
        self.preferences = preferences
    }

    var isTodaySelected: Bool {
        selectedDate == DiningFetcher.formatDate(.now)
    }

    var dailyCalorieTarget: Int? {
        response?.dailyCalorieTarget ?? nutritionRepository.snapshot.profile?.dailyCalories
    }

    var activeCaloriesToday: Int? {
        activeCaloriesLocal ?? response?.activeCaloriesToday
    }

    var visibleSuggestions: [MealSuggestion] {
        let meals = response?.meals ?? []
        guard !availableMealSlots.isEmpty else {
            return meals.sorted { lhs, rhs in
                (mealOrder[lhs.meal] ?? 99) < (mealOrder[rhs.meal] ?? 99)
            }
        }

        let orderLookup = Dictionary(uniqueKeysWithValues: availableMealSlots.enumerated().map { ($1, $0) })
        let allowed = Set(availableMealSlots)
        return meals
            .filter { allowed.contains($0.meal) }
            .sorted { lhs, rhs in
                (orderLookup[lhs.meal] ?? .max) < (orderLookup[rhs.meal] ?? .max)
            }
    }

    var canMarkMealsConsumed: Bool {
        !isFutureDateString(selectedDate)
    }

    func load(for date: String) async {
        selectedDate = date
        availableMealSlots = []
        syncFromRepository(for: date)
        await refresh(for: date)
    }

    func refreshCurrentDate() async {
        await refresh(for: selectedDate)
    }

    func toggleConsumed(_ suggestion: MealSuggestion) {
        if repository.isMealConsumed(mealKey: suggestion.mealKey, date: selectedDate) {
            repository.unmarkMealConsumed(mealKey: suggestion.mealKey, date: selectedDate)
        } else {
            repository.markMealConsumed(suggestion, date: selectedDate)
        }
        syncConsumption(for: selectedDate)
    }

    func isConsumed(_ suggestion: MealSuggestion) -> Bool {
        repository.isMealConsumed(mealKey: suggestion.mealKey, date: selectedDate)
    }

    private func refresh(for date: String) async {
        guard !isRefreshing else { return }
        selectedDate = date
        isRefreshing = true
        defer { isRefreshing = false }

        await nutritionRepository.loadIfNeeded()
        await fetcher.ensureDataAvailable(for: date)
        syncFromRepository(for: date)
        await refreshLocalHealthMetrics(for: date)

        guard fetcher.menuData[date] != nil, let diningMenu = fetcher.diningMenu else {
            response = nil
            availableMealSlots = []
            state = .empty("No dining data is available for \(formattedDateTitle(from: date)).")
            return
        }

        let visibility = MenuVisibilityPreferences(preferences: preferences)
        let mealSlots = diningMenu.suggestionMealSlots(for: date, preferences: visibility)
        availableMealSlots = mealSlots

        guard !mealSlots.isEmpty else {
            response = nil
            state = .empty("No visible menu items match your current filters for \(formattedDateTitle(from: date)).")
            return
        }

        if response == nil {
            state = .loading
        }

        let preferencesPayload = SuggestionsPreferencesPayload(preferences: preferences)
        let menuExport = diningMenu.exportSuggestionsForLLM(date: date, preferences: visibility)
        let cacheKey = suggestionsCacheKey(
            date: date,
            mealSlots: mealSlots,
            preferences: preferencesPayload,
            nutritionProfile: nutritionRepository.snapshot.profile,
            menuExport: menuExport
        )

        if let cachedSnapshot = repository.cachedSnapshot(for: date), cachedSnapshot.cacheKey == cacheKey {
            response = cachedSnapshot.response
            state = cachedSnapshot.response.meals.isEmpty
                ? .empty("No meal suggestions were saved for \(formattedDateTitle(from: date)).")
                : .ready
            return
        }

        do {
            _ = await healthKitService.requestAuthorizationIfNeeded()
            let healthSnapshot = await healthKitService.fetchNutritionSnapshot()

            let payload = SuggestionsRequestPayload(
                schemaVersion: suggestionsSchemaVersion,
                date: date,
                mealSlots: mealSlots,
                preferences: preferencesPayload,
                nutritionProfile: nutritionRepository.snapshot.profile,
                healthkit: SuggestionsHealthContextPayload(
                    snapshot: healthSnapshot,
                    activeCaloriesToday: activeCaloriesLocal
                ),
                menuExport: menuExport,
                clientContext: SuggestionsClientContextPayload(
                    consumedMealKeys: repository.consumedMeals(for: date).map(\.mealKey)
                )
            )

            let freshResponse = try await apiClient.fetchSuggestions(payload)
            repository.saveSuggestions(freshResponse, cacheKey: cacheKey)
            response = freshResponse
            state = freshResponse.meals.isEmpty
                ? .empty("No meal suggestions were returned for \(formattedDateTitle(from: date)).")
                : .ready
            syncConsumption(for: date)
        } catch {
            if response != nil {
                state = .ready
            } else {
                state = .failed(error.localizedDescription)
            }
        }
    }

    private func syncFromRepository(for date: String) {
        if let cachedResponse = repository.cachedSuggestions(for: date) {
            response = cachedResponse
            state = cachedResponse.meals.isEmpty
                ? .empty("No meal suggestions were saved for \(formattedDateTitle(from: date)).")
                : .ready
        } else if case .failed = state {
            // Preserve explicit error state until a new result arrives.
        } else {
            response = nil
            state = .idle
        }

        syncConsumption(for: date)
    }

    private func refreshLocalHealthMetrics(for date: String) async {
        guard date == DiningFetcher.formatDate(.now) else {
            activeCaloriesLocal = nil
            return
        }

        _ = await healthKitService.requestAuthorizationIfNeeded()
        if let todayCalories = await healthKitService.fetchTodayActiveCalories() {
            activeCaloriesLocal = Int(todayCalories.rounded())
        } else {
            activeCaloriesLocal = nil
        }
    }

    private func syncConsumption(for date: String) {
        consumedMeals = repository.consumedMeals(for: date)
        consumedCalories = repository.consumedCalories(for: date)
    }

    private func formattedDateTitle(from date: String) -> String {
        guard let resolvedDate = SuggestionsViewModel.dateFormatter.date(from: date) else {
            return date
        }
        return resolvedDate.formatted(date: .abbreviated, time: .omitted)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

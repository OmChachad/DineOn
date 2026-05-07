//
//  SuggestionsRepository.swift
//  DineOn
//
//  Created by Codex on 05/06/26.
//

import Foundation
import Combine

@MainActor
final class SuggestionsRepository: ObservableObject {
    static let shared = SuggestionsRepository()

    @Published private(set) var cachedSuggestionsByDate: [String: DateScopedSuggestionSnapshot]
    @Published private(set) var consumedMealsByDate: [String: [ConsumedMealLogEntry]]

    private let userDefaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private let suggestionsDefaultsKey = "suggestionsCacheByDate"
    private let consumedMealsDefaultsKey = "suggestionsConsumedMealsByDate"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults

        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        cachedSuggestionsByDate = SuggestionsRepository.loadValue(
            forKey: suggestionsDefaultsKey,
            from: userDefaults,
            decoder: decoder,
            defaultValue: [:]
        )
        consumedMealsByDate = SuggestionsRepository.loadValue(
            forKey: consumedMealsDefaultsKey,
            from: userDefaults,
            decoder: decoder,
            defaultValue: [:]
        )
    }

    func cachedSuggestions(for date: String) -> MealSuggestionResponse? {
        cachedSuggestionsByDate[date]?.response
    }

    func saveSuggestions(_ response: MealSuggestionResponse) {
        cachedSuggestionsByDate[response.date] = DateScopedSuggestionSnapshot(date: response.date, response: response)
        persist(cachedSuggestionsByDate, forKey: suggestionsDefaultsKey)
    }

    func consumedMeals(for date: String) -> [ConsumedMealLogEntry] {
        (consumedMealsByDate[date] ?? []).sorted { lhs, rhs in
            if lhs.meal == rhs.meal {
                return lhs.consumedAt < rhs.consumedAt
            }
            return (mealOrder[lhs.meal] ?? 99) < (mealOrder[rhs.meal] ?? 99)
        }
    }

    func isMealConsumed(mealKey: String, date: String) -> Bool {
        consumedMealsByDate[date]?.contains(where: { $0.mealKey == mealKey }) ?? false
    }

    func markMealConsumed(_ suggestion: MealSuggestion, date: String) {
        var entries = consumedMealsByDate[date] ?? []
        guard !entries.contains(where: { $0.mealKey == suggestion.mealKey }) else {
            return
        }

        entries.append(ConsumedMealLogEntry(date: date, suggestion: suggestion))
        consumedMealsByDate[date] = entries
        persist(consumedMealsByDate, forKey: consumedMealsDefaultsKey)
    }

    func unmarkMealConsumed(mealKey: String, date: String) {
        var entries = consumedMealsByDate[date] ?? []
        entries.removeAll { $0.mealKey == mealKey }
        consumedMealsByDate[date] = entries
        persist(consumedMealsByDate, forKey: consumedMealsDefaultsKey)
    }

    func consumedCalories(for date: String) -> Int {
        consumedMeals(for: date).compactMap(\.estimatedCalories).reduce(0, +)
    }

    private func persist<T: Encodable>(_ value: T, forKey key: String) {
        do {
            let data = try encoder.encode(value)
            userDefaults.set(data, forKey: key)
        } catch {
            print("❌ Failed to persist suggestions data for \(key): \(error.localizedDescription)")
        }
    }

    private static func loadValue<T: Decodable>(
        forKey key: String,
        from userDefaults: UserDefaults,
        decoder: JSONDecoder,
        defaultValue: T
    ) -> T {
        guard let data = userDefaults.data(forKey: key) else {
            return defaultValue
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            print("❌ Failed to decode suggestions data for \(key): \(error.localizedDescription)")
            return defaultValue
        }
    }
}

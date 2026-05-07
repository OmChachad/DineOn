//
//  SuggestionsModels.swift
//  DineOn
//
//  Created by Codex on 05/06/26.
//

import Foundation
import CryptoKit

let suggestionsSchemaVersion = 1

struct MealSuggestion: Codable, Equatable, Identifiable {
    var id: String { mealKey }

    let meal: String
    let mealKey: String
    let venue: String
    let items: [String]
    let estimatedCalories: Int?
    let estimatedProteinG: Int?
    let estimatedCarbsG: Int?
    let estimatedFatG: Int?
    let rationale: String
    let optionalCaution: String?
}

struct MealSuggestionResponse: Codable, Equatable {
    let schemaVersion: Int
    let generatedAt: Date
    let date: String
    let dailyCalorieTarget: Int?
    let activeCaloriesToday: Int?
    let meals: [MealSuggestion]
    let summary: String
    let warnings: [String]
}

struct DateScopedSuggestionSnapshot: Codable, Equatable {
    let date: String
    let cacheKey: String
    let response: MealSuggestionResponse
}

struct ConsumedMealLogEntry: Codable, Equatable, Identifiable {
    var id: String { "\(date)::\(mealKey)" }

    let date: String
    let meal: String
    let mealKey: String
    let venue: String
    let items: [String]
    let estimatedCalories: Int?
    let estimatedProteinG: Int?
    let estimatedCarbsG: Int?
    let estimatedFatG: Int?
    let consumedAt: Date

    init(date: String, suggestion: MealSuggestion, consumedAt: Date = .now) {
        self.date = date
        self.meal = suggestion.meal
        self.mealKey = suggestion.mealKey
        self.venue = suggestion.venue
        self.items = suggestion.items
        self.estimatedCalories = suggestion.estimatedCalories
        self.estimatedProteinG = suggestion.estimatedProteinG
        self.estimatedCarbsG = suggestion.estimatedCarbsG
        self.estimatedFatG = suggestion.estimatedFatG
        self.consumedAt = consumedAt
    }
}

struct SuggestionsPreferencesPayload: Codable {
    let hasAAZAccess: Bool
    let hasDietaryRestrictions: Bool
    let selectedAllergens: [String]
    let selectedDietaryPreferences: [String]
    let excludedKeywords: [String]
    let favoriteDishes: [String]

    init(preferences: Preferences) {
        hasAAZAccess = preferences.hasAAZAccess
        hasDietaryRestrictions = preferences.hasDietaryRestrictions
        selectedAllergens = preferences.selectedAllergens.sorted()
        selectedDietaryPreferences = preferences.selectedDietaryPreferences.sorted()
        excludedKeywords = preferences.excludedKeywords.sorted()
        favoriteDishes = preferences.favoriteDishes.sorted()
    }

    enum CodingKeys: String, CodingKey {
        case hasAAZAccess = "has_aaz_access"
        case hasDietaryRestrictions = "has_dietary_restrictions"
        case selectedAllergens = "selected_allergens"
        case selectedDietaryPreferences = "selected_dietary_preferences"
        case excludedKeywords = "excluded_keywords"
        case favoriteDishes = "favorite_dishes"
    }
}

struct SuggestionsHealthContextPayload: Codable {
    let age: Int?
    let sex: HealthKitSnapshot.Sex?
    let heightCm: Double?
    let weightKg: Double?
    let bmi: Double?
    let restingCalories: Double?
    let activeCaloriesAvg: Double?
    let tdee: Double?
    let stepsDailyAvg: Double?
    let exerciseSessionsPerWeek: Double?
    let sleepHrsAvg: Double?
    let restingHrAvg: Double?
    let weightTrend30dKg: Double?
    let activeCaloriesToday: Int?

    init(snapshot: HealthKitSnapshot, activeCaloriesToday: Int?) {
        age = snapshot.age
        sex = snapshot.sex
        heightCm = snapshot.heightCm
        weightKg = snapshot.weightKg
        bmi = snapshot.bmi
        restingCalories = snapshot.restingCalories
        activeCaloriesAvg = snapshot.activeCaloriesAvg
        tdee = snapshot.tdee
        stepsDailyAvg = snapshot.stepsDailyAvg
        exerciseSessionsPerWeek = snapshot.exerciseSessionsPerWeek
        sleepHrsAvg = snapshot.sleepHrsAvg
        restingHrAvg = snapshot.restingHrAvg
        weightTrend30dKg = snapshot.weightTrend30dKg
        self.activeCaloriesToday = activeCaloriesToday
    }

    enum CodingKeys: String, CodingKey {
        case age
        case sex
        case heightCm = "height_cm"
        case weightKg = "weight_kg"
        case bmi
        case restingCalories = "resting_calories"
        case activeCaloriesAvg = "active_calories_avg"
        case tdee
        case stepsDailyAvg = "steps_daily_avg"
        case exerciseSessionsPerWeek = "exercise_sessions_per_week"
        case sleepHrsAvg = "sleep_hrs_avg"
        case restingHrAvg = "resting_hr_avg"
        case weightTrend30dKg = "weight_trend_30d_kg"
        case activeCaloriesToday = "active_calories_today"
    }
}

struct SuggestionsClientContextPayload: Codable {
    let consumedMealKeys: [String]

    enum CodingKeys: String, CodingKey {
        case consumedMealKeys = "consumed_meal_keys"
    }
}

struct SuggestionsRequestPayload: Codable {
    let schemaVersion: Int
    let date: String
    let mealSlots: [String]
    let preferences: SuggestionsPreferencesPayload
    let nutritionProfile: NutritionProfile?
    let healthkit: SuggestionsHealthContextPayload
    let menuExport: String
    let clientContext: SuggestionsClientContextPayload

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case date
        case mealSlots = "meal_slots"
        case preferences
        case nutritionProfile = "nutrition_profile"
        case healthkit
        case menuExport = "menu_export"
        case clientContext = "client_context"
    }
}

struct SuggestionsCacheKeyInput: Codable {
    let date: String
    let mealSlots: [String]
    let preferences: SuggestionsPreferencesPayload
    let nutritionProfile: NutritionProfile?
    let menuExport: String
}

func suggestionsCacheKey(
    date: String,
    mealSlots: [String],
    preferences: SuggestionsPreferencesPayload,
    nutritionProfile: NutritionProfile?,
    menuExport: String
) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    encoder.dateEncodingStrategy = .iso8601

    let input = SuggestionsCacheKeyInput(
        date: date,
        mealSlots: mealSlots,
        preferences: preferences,
        nutritionProfile: nutritionProfile,
        menuExport: menuExport
    )

    guard let data = try? encoder.encode(input) else {
        return "\(date)::\(mealSlots.joined(separator: ","))::\(menuExport.count)"
    }

    let digest = SHA256.hash(data: data)
    return digest.map { String(format: "%02x", $0) }.joined()
}

enum SuggestionsState: Equatable {
    case idle
    case loading
    case ready
    case empty(String)
    case failed(String)
}

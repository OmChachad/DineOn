//
//  NutritionProfileModels.swift
//  DineOn
//
//  Created by Codex on 05/06/26.
//

import Foundation

let nutritionProfileSchemaVersion = 1
let maxNutritionPreferenceLength = 150

struct NutritionPreferenceEntry: Identifiable, Codable, Hashable {
    var id: UUID
    var text: String

    init(id: UUID = UUID(), text: String = "") {
        self.id = id
        self.text = text
    }

    var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct NutritionPreferencesDraft: Codable, Equatable {
    var entries: [NutritionPreferenceEntry] = [NutritionPreferenceEntry()]

    var normalizedForEditing: NutritionPreferencesDraft {
        var copy = self
        copy.ensureTrailingEmptyEntry()
        return copy
    }

    var normalizedForStorage: NutritionPreferencesDraft {
        let meaningfulEntries = entries.filter { !$0.trimmedText.isEmpty }
        if meaningfulEntries.isEmpty {
            return NutritionPreferencesDraft(entries: [NutritionPreferenceEntry()])
        }
        return NutritionPreferencesDraft(entries: meaningfulEntries + [NutritionPreferenceEntry()])
    }

    var trimmedNotes: [String] {
        entries
            .map(\.trimmedText)
            .filter { !$0.isEmpty }
    }

    mutating func ensureTrailingEmptyEntry() {
        if entries.isEmpty {
            entries = [NutritionPreferenceEntry()]
            return
        }

        if entries.count > 1 {
            let lastIndex = entries.indices.last ?? 0
            let filtered = entries.enumerated().filter { index, entry in
                !entry.trimmedText.isEmpty || index == lastIndex
            }.map(\.element)
            entries = filtered
        }

        if !(entries.last?.trimmedText.isEmpty ?? false) {
            entries.append(NutritionPreferenceEntry())
        }
    }
}

struct HealthKitSnapshot: Codable, Equatable {
    enum Sex: String, Codable, Equatable {
        case female
        case male
        case other
        case unknown
    }

    var age: Int?
    var sex: Sex?
    var heightCm: Double?
    var weightKg: Double?
    var bmi: Double?
    var restingCalories: Double?
    var activeCaloriesAvg: Double?
    var tdee: Double?
    var stepsDailyAvg: Double?
    var exerciseSessionsPerWeek: Double?
    var sleepHrsAvg: Double?
    var restingHrAvg: Double?
    var weightTrend30dKg: Double?

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
    }
}

struct NutritionProfile: Codable, Equatable {
    let schemaVersion: Int
    let generatedAt: Date
    let dailyCalories: Int?
    let proteinG: Int?
    let carbsG: Int?
    let fatG: Int?
    let calorieRationale: String
    let mealPattern: String
    let foodsToPrioritize: [String]
    let foodsToAvoid: [String]
    let watchNutrients: [String]
    let sleepNote: String
    let summary: String
    let sources: [String]
    let warnings: [String]
}

struct NutritionProfileStoredSnapshot: Codable, Equatable {
    var draft: NutritionPreferencesDraft = NutritionPreferencesDraft()
    var analyzedPreferenceNotes: [String] = []
    var profile: NutritionProfile?
}

struct NutritionProfileState: Equatable {
    enum Phase: Equatable {
        case idle
        case loading
        case ready
        case saving
        case failed(String)
    }

    var phase: Phase = .idle
    var isDirty: Bool = false
}

struct NutritionProfileRequestPayload: Codable {
    let schemaVersion: Int
    let preferenceNotes: [String]
    let healthkit: HealthKitSnapshot

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case preferenceNotes = "preference_notes"
        case healthkit
    }
}

enum NutritionProfileValidationError: LocalizedError {
    case empty
    case tooLong

    var errorDescription: String? {
        switch self {
        case .empty:
            return "Add at least one nutrition goal or preference before saving."
        case .tooLong:
            return "Each preference must be 150 characters or fewer."
        }
    }
}

//
//  HealthKitNutritionService.swift
//  DineOn
//
//  Created by Codex on 05/06/26.
//

import Foundation
import HealthKit

@MainActor
final class HealthKitNutritionService {
    static let shared = HealthKitNutritionService()

    private let healthStore = HKHealthStore()

    private init() {}

    var statusSummary: String {
        guard HKHealthStore.isHealthDataAvailable() else {
            return "HealthKit is not available on this device."
        }

        let stepStatus = healthStore.authorizationStatus(for: HKQuantityType(.stepCount))
        switch stepStatus {
        case .notDetermined:
            return "HealthKit access is optional. Connect it to personalize calorie and activity targets."
        case .sharingAuthorized:
            return "HealthKit is connected. DineOn will fetch a fresh snapshot when you save."
        case .sharingDenied:
            return "HealthKit access looks limited or denied. DineOn can still analyze your text preferences."
        @unknown default:
            return "HealthKit status is unavailable."
        }
    }

    func requestAuthorizationIfNeeded() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }

        do {
            try await healthStore.requestAuthorization(toShare: [], read: readTypes)
            return true
        } catch {
            print("❌ HealthKit authorization failed: \(error.localizedDescription)")
            return false
        }
    }

    func fetchNutritionSnapshot() async -> HealthKitSnapshot {
        guard HKHealthStore.isHealthDataAvailable() else {
            return HealthKitSnapshot()
        }

        async let age = fetchAge()
        async let sex = fetchSex()
        async let heightCm = mostRecentQuantity(for: .height, unit: .meterUnit(with: .centi))
        async let weightKg = mostRecentQuantity(for: .bodyMass, unit: .gramUnit(with: .kilo))
        async let bmiValue = mostRecentQuantity(for: .bodyMassIndex, unit: .count())
        async let restingCalories = averageDailyCumulativeQuantity(for: .basalEnergyBurned, unit: .kilocalorie(), days: 7)
        async let activeCalories = averageDailyCumulativeQuantity(for: .activeEnergyBurned, unit: .kilocalorie(), days: 7)
        async let stepsDailyAvg = averageDailyCumulativeQuantity(for: .stepCount, unit: .count(), days: 7)
        async let restingHeartRate = averageDiscreteQuantity(
            for: .restingHeartRate,
            unit: HKUnit.count().unitDivided(by: .minute()),
            days: 30
        )
        async let exerciseSessionsPerWeek = averageWorkoutSessionsPerWeek()
        async let sleepHours = averageSleepHours(days: 14)
        async let weightTrend = weightTrend30d()

        let resolvedAge = await age
        let resolvedSex = await sex
        let resolvedHeightCm = await heightCm
        let resolvedWeightKg = await weightKg
        let resolvedBMI = await bmiValue
        let resolvedRestingCalories = await restingCalories
        let resolvedActiveCalories = await activeCalories

        var snapshot = HealthKitSnapshot(
            age: resolvedAge,
            sex: resolvedSex,
            heightCm: resolvedHeightCm,
            weightKg: resolvedWeightKg,
            bmi: resolvedBMI,
            restingCalories: resolvedRestingCalories,
            activeCaloriesAvg: resolvedActiveCalories,
            tdee: nil,
            stepsDailyAvg: await stepsDailyAvg,
            exerciseSessionsPerWeek: await exerciseSessionsPerWeek,
            sleepHrsAvg: await sleepHours,
            restingHrAvg: await restingHeartRate,
            weightTrend30dKg: await weightTrend
        )

        if snapshot.tdee == nil, let resting = resolvedRestingCalories, let active = resolvedActiveCalories {
            snapshot.tdee = rounded(resting + active)
        }
        if snapshot.bmi == nil, let heightCm = resolvedHeightCm, let weightKg = resolvedWeightKg, heightCm > 0 {
            let heightMeters = heightCm / 100
            snapshot.bmi = rounded(weightKg / (heightMeters * heightMeters))
        }
        return snapshot
    }

    func fetchTodayActiveCalories() async -> Double? {
        guard HKHealthStore.isHealthDataAvailable() else {
            return nil
        }

        let calendar = Calendar.current
        let startDate = calendar.startOfDay(for: Date())
        guard let endDate = calendar.date(byAdding: .day, value: 1, to: startDate) else {
            return nil
        }

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate)
        let samplePredicate = HKSamplePredicate.quantitySample(
            type: HKQuantityType(.activeEnergyBurned),
            predicate: predicate
        )

        let descriptor = HKStatisticsQueryDescriptor(
            predicate: samplePredicate,
            options: .cumulativeSum
        )

        do {
            let result = try await descriptor.result(for: healthStore)
            guard let value = result?.sumQuantity()?.doubleValue(for: .kilocalorie()) else {
                return nil
            }
            return rounded(value)
        } catch {
            return nil
        }
    }

    private var readTypes: Set<HKObjectType> {
        [
            HKCharacteristicType(.dateOfBirth),
            HKCharacteristicType(.biologicalSex),
            HKQuantityType(.height),
            HKQuantityType(.bodyMass),
            HKQuantityType(.bodyMassIndex),
            HKQuantityType(.basalEnergyBurned),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.stepCount),
            HKQuantityType(.restingHeartRate),
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
            HKObjectType.workoutType()
        ]
    }

    private func fetchAge() async -> Int? {
        do {
            let birthDate = try healthStore.dateOfBirthComponents()
            guard let date = Calendar.current.date(from: birthDate) else { return nil }
            return Calendar.current.dateComponents([.year], from: date, to: Date()).year
        } catch {
            return nil
        }
    }

    private func fetchSex() async -> HealthKitSnapshot.Sex? {
        do {
            switch try healthStore.biologicalSex().biologicalSex {
            case .female:
                return .female
            case .male:
                return .male
            case .other:
                return .other
            case .notSet:
                return .unknown
            @unknown default:
                return .unknown
            }
        } catch {
            return nil
        }
    }

    private func mostRecentQuantity(for identifier: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double? {
        let quantityType = HKQuantityType(identifier)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: quantityType)],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 1
        )

        do {
            let samples = try await descriptor.result(for: healthStore)
            guard let sample = samples.first else { return nil }
            return rounded(sample.quantity.doubleValue(for: unit))
        } catch {
            return nil
        }
    }

    private func averageDailyCumulativeQuantity(
        for identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        days: Int
    ) async -> Double? {
        let calendar = Calendar.current
        let endDate = calendar.startOfDay(for: Date())
        guard let startDate = calendar.date(byAdding: .day, value: -days, to: endDate) else { return nil }

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate)
        let samplePredicate = HKSamplePredicate.quantitySample(
            type: HKQuantityType(identifier),
            predicate: predicate
        )

        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: samplePredicate,
            options: .cumulativeSum,
            anchorDate: endDate,
            intervalComponents: DateComponents(day: 1)
        )

        do {
            let result = try await descriptor.result(for: healthStore)
            var values: [Double] = []
            result.enumerateStatistics(from: startDate, to: endDate) { statistics, _ in
                if let value = statistics.sumQuantity()?.doubleValue(for: unit) {
                    values.append(value)
                }
            }
            guard !values.isEmpty else { return nil }
            return rounded(values.reduce(0, +) / Double(values.count))
        } catch {
            return nil
        }
    }

    private func averageDiscreteQuantity(
        for identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        days: Int
    ) async -> Double? {
        let calendar = Calendar.current
        let endDate = Date()
        guard let startDate = calendar.date(byAdding: .day, value: -days, to: endDate) else { return nil }

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate)
        let samplePredicate = HKSamplePredicate.quantitySample(
            type: HKQuantityType(identifier),
            predicate: predicate
        )

        let descriptor = HKStatisticsQueryDescriptor(
            predicate: samplePredicate,
            options: .discreteAverage
        )

        do {
            let result = try await descriptor.result(for: healthStore)
            guard let value = result?.averageQuantity()?.doubleValue(for: unit) else { return nil }
            return rounded(value)
        } catch {
            return nil
        }
    }

    private func averageWorkoutSessionsPerWeek() async -> Double? {
        let calendar = Calendar.current
        let endDate = Date()
        guard let startDate = calendar.date(byAdding: .day, value: -28, to: endDate) else { return nil }

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(predicate)],
            sortDescriptors: [],
            limit: HKObjectQueryNoLimit
        )

        do {
            let workouts = try await descriptor.result(for: healthStore)
            return rounded(Double(workouts.count) / 4.0)
        } catch {
            return nil
        }
    }

    private func averageSleepHours(days: Int) async -> Double? {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return nil }
        let calendar = Calendar.current
        let endDate = Date()
        guard let startDate = calendar.date(byAdding: .day, value: -days, to: endDate) else { return nil }

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: sleepType, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)],
            limit: HKObjectQueryNoLimit
        )

        do {
            let samples = try await descriptor.result(for: healthStore)
            let asleepValues: Set<Int> = [
                HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                HKCategoryValueSleepAnalysis.asleepREM.rawValue
            ]

            let totalSeconds = samples
                .filter { asleepValues.contains($0.value) }
                .reduce(0.0) { partialResult, sample in
                    partialResult + sample.endDate.timeIntervalSince(sample.startDate)
                }

            return totalSeconds > 0 ? rounded((totalSeconds / 3600) / Double(days)) : nil
        } catch {
            return nil
        }
    }

    private func weightTrend30d() async -> Double? {
        let quantityType = HKQuantityType(.bodyMass)
        let calendar = Calendar.current
        let endDate = Date()
        guard let startDate = calendar.date(byAdding: .day, value: -30, to: endDate) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: quantityType, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.endDate, order: .forward)],
            limit: HKObjectQueryNoLimit
        )

        do {
            let samples = try await descriptor.result(for: healthStore)
            guard
                let first = samples.first?.quantity.doubleValue(for: .gramUnit(with: .kilo)),
                let last = samples.last?.quantity.doubleValue(for: .gramUnit(with: .kilo))
            else {
                return nil
            }
            return rounded(last - first)
        } catch {
            return nil
        }
    }

    private func rounded(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }
}

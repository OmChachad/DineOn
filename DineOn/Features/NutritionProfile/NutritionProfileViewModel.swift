//
//  NutritionProfileViewModel.swift
//  DineOn
//
//  Created by Codex on 05/06/26.
//

import Foundation
import Combine

@MainActor
final class NutritionProfileViewModel: ObservableObject {
    @Published var draft = NutritionPreferencesDraft()
    @Published private(set) var savedProfile: NutritionProfile?
    @Published var state = NutritionProfileState()
    @Published private(set) var analyzedPreferenceNotes: [String] = []
    @Published private(set) var healthStatusSummary = HealthKitNutritionService.shared.statusSummary

    private let repository: NutritionProfileRepository
    private let apiClient: NutritionProfileAPIClient
    private let healthKitService: HealthKitNutritionService
    private var hasLoaded = false

    convenience init() {
        self.init(
            repository: .shared,
            apiClient: .shared,
            healthKitService: .shared
        )
    }

    init(
        repository: NutritionProfileRepository,
        apiClient: NutritionProfileAPIClient,
        healthKitService: HealthKitNutritionService
    ) {
        self.repository = repository
        self.apiClient = apiClient
        self.healthKitService = healthKitService
    }

    var saveButtonTitle: String {
        state.phase == .saving ? "Analyzing…" : "Save & Analyze"
    }

    var lastUpdatedText: String {
        guard let date = savedProfile?.generatedAt else { return "Not analyzed yet" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    var canSave: Bool {
        state.phase != .saving
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        state.phase = .loading
        await repository.loadIfNeeded()
        syncFromRepository()
        state.phase = .ready
    }

    func requestHealthKitAccess() async {
        _ = await healthKitService.requestAuthorizationIfNeeded()
        healthStatusSummary = healthKitService.statusSummary
    }

    func handleTextChange() {
        draft.ensureTrailingEmptyEntry()
        state.isDirty = currentTrimmedNotes != analyzedPreferenceNotes
        scheduleDraftPersistence()
    }

    func removeEntry(id: UUID) {
        draft.entries.removeAll { $0.id == id }
        draft.ensureTrailingEmptyEntry()
        state.isDirty = currentTrimmedNotes != analyzedPreferenceNotes
        scheduleDraftPersistence()
    }

    func saveAndAnalyze() async {
        do {
            let notes = try validatedNotes()
            state.phase = .saving
            healthStatusSummary = healthKitService.statusSummary
            _ = await healthKitService.requestAuthorizationIfNeeded()
            let snapshot = await healthKitService.fetchNutritionSnapshot()
            healthStatusSummary = healthKitService.statusSummary
            let profile = try await apiClient.analyze(preferenceNotes: notes, healthkit: snapshot)
            savedProfile = profile
            analyzedPreferenceNotes = notes
            state = NutritionProfileState(phase: .ready, isDirty: false)
            await repository.storeSuccessfulAnalysis(draft: draft, analyzedNotes: notes, profile: profile)
            syncFromRepository()
        } catch {
            state.phase = .failed(error.localizedDescription)
        }
    }

    private func validatedNotes() throws -> [String] {
        let notes = currentTrimmedNotes
        guard !notes.isEmpty else {
            throw NutritionProfileValidationError.empty
        }
        guard notes.allSatisfy({ $0.count <= maxNutritionPreferenceLength }) else {
            throw NutritionProfileValidationError.tooLong
        }
        return notes
    }

    private var currentTrimmedNotes: [String] {
        draft.trimmedNotes
    }

    private func scheduleDraftPersistence() {
        let snapshotDraft = draft.normalizedForStorage
        Task { [repository] in
            await repository.persistDraft(snapshotDraft)
        }
    }

    private func syncFromRepository() {
        draft = repository.snapshot.draft.normalizedForEditing
        analyzedPreferenceNotes = repository.snapshot.analyzedPreferenceNotes
        savedProfile = repository.snapshot.profile
        state.isDirty = currentTrimmedNotes != analyzedPreferenceNotes
        healthStatusSummary = healthKitService.statusSummary
    }
}

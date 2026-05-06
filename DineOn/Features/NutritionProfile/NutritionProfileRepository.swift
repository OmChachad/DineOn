//
//  NutritionProfileRepository.swift
//  DineOn
//
//  Created by Codex on 05/06/26.
//

import Foundation
import Combine

@MainActor
final class NutritionProfileRepository: ObservableObject {
    static let shared = NutritionProfileRepository()

    @Published private(set) var snapshot = NutritionProfileStoredSnapshot()

    private let fileStore: NutritionProfileFileStore
    private var hasLoaded = false

    init(fileStore: NutritionProfileFileStore = NutritionProfileFileStore()) {
        self.fileStore = fileStore
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true

        do {
            snapshot = try await fileStore.load().normalizedForEditing
        } catch {
            print("❌ Failed to load nutrition profile snapshot: \(error.localizedDescription)")
            snapshot = NutritionProfileStoredSnapshot()
        }
    }

    func persistDraft(_ draft: NutritionPreferencesDraft) async {
        snapshot.draft = draft.normalizedForStorage
        await saveSnapshot()
    }

    func storeSuccessfulAnalysis(
        draft: NutritionPreferencesDraft,
        analyzedNotes: [String],
        profile: NutritionProfile
    ) async {
        snapshot = NutritionProfileStoredSnapshot(
            draft: draft.normalizedForStorage,
            analyzedPreferenceNotes: analyzedNotes,
            profile: profile
        )
        await saveSnapshot()
    }

    private func saveSnapshot() async {
        do {
            try await fileStore.save(snapshot)
        } catch {
            print("❌ Failed to save nutrition profile snapshot: \(error.localizedDescription)")
        }
    }
}

private extension NutritionProfileStoredSnapshot {
    var normalizedForEditing: NutritionProfileStoredSnapshot {
        NutritionProfileStoredSnapshot(
            draft: draft.normalizedForEditing,
            analyzedPreferenceNotes: analyzedPreferenceNotes,
            profile: profile
        )
    }
}

//
//  NutritionProfileView.swift
//  DineOn
//
//  Created by Codex on 05/06/26.
//

import SwiftUI

struct NutritionProfileView: View {
    @StateObject private var viewModel = NutritionProfileViewModel()

    var body: some View {
        Form {
            Section("Nutrition Goals") {
                ForEach($viewModel.draft.entries) { $entry in
                    HStack(alignment: .top, spacing: 12) {
                        TextField(
                            "Example: I want more energy and higher-protein vegetarian meals",
                            text: $entry.text,
                            axis: .vertical
                        )
                        .lineLimit(2...4)
                        .onChange(of: entry.text) { _, _ in
                            viewModel.handleTextChange()
                        }

                        if !entry.trimmedText.isEmpty || viewModel.draft.entries.count > 1 {
                            Button(role: .destructive) {
                                viewModel.removeEntry(id: entry.id)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Text("Each note is capped at 150 characters. DineOn only re-analyzes when you tap Save & Analyze.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("HealthKit") {
                Text(viewModel.healthStatusSummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button("Connect HealthKit") {
                    Task { await viewModel.requestHealthKitAccess() }
                }
            }

            Section("Saved Profile") {
                Label(viewModel.lastUpdatedText, systemImage: "clock")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let profile = viewModel.savedProfile {
                    if let dailyCalories = profile.dailyCalories {
                        metricRow(title: "Daily Calories", value: "\(dailyCalories) kcal")
                    }

                    HStack(spacing: 12) {
                        if let protein = profile.proteinG {
                            macroChip(title: "Protein", value: "\(protein)g")
                        }
                        if let carbs = profile.carbsG {
                            macroChip(title: "Carbs", value: "\(carbs)g")
                        }
                        if let fat = profile.fatG {
                            macroChip(title: "Fat", value: "\(fat)g")
                        }
                    }
                    .padding(.vertical, 4)

                    Text(profile.summary)
                        .font(.subheadline)

                    if !profile.warnings.isEmpty {
                        ForEach(profile.warnings, id: \.self) { warning in
                            Label(warning, systemImage: "exclamationmark.triangle.fill")
                                .font(.footnote)
                                .foregroundStyle(.orange)
                        }
                    }
                } else {
                    Text("No nutrition profile has been generated yet.")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button {
                    Task { await viewModel.saveAndAnalyze() }
                } label: {
                    HStack {
                        if viewModel.state.phase == .saving {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(viewModel.saveButtonTitle)
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(!viewModel.canSave)
            }
        }
        .navigationTitle("Nutrition Profile")
        .task {
            await viewModel.loadIfNeeded()
        }
        .alert(
            "Nutrition Profile",
            isPresented: Binding(
                get: {
                    if case .failed = viewModel.state.phase {
                        return true
                    }
                    return false
                },
                set: { _ in
                    viewModel.state.phase = .ready
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            if case .failed(let message) = viewModel.state.phase {
                Text(message)
            }
        }
    }

    @ViewBuilder
    private func metricRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func macroChip(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct NutritionProfileSummaryCard: View {
    @ObservedObject var repository: NutritionProfileRepository

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Nutrition Profile", systemImage: "fork.knife.circle.fill")
                    .font(.headline)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }

            if let profile = repository.snapshot.profile {
                HStack(spacing: 12) {
                    if let calories = profile.dailyCalories {
                        summaryPill(title: "Calories", value: "\(calories)")
                    }
                    if let protein = profile.proteinG {
                        summaryPill(title: "Protein", value: "\(protein)g")
                    }
                }

                Text(profile.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            } else {
                Text("Save your nutrition goals and HealthKit snapshot to generate reusable calorie and macro targets for later meal planning.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func summaryPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

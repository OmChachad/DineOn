//
//  SuggestionsView.swift
//  DineOn
//
//  Created by Codex on 05/06/26.
//

import SwiftUI

struct SuggestionsView: View {
    let chosenDate: String
    let isVisible: Bool

    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel = SuggestionsViewModel()
    @StateObject private var nutritionRepository = NutritionProfileRepository.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                nutritionProfileSection

                if viewModel.isTodaySelected {
                    metricsSection
                }

                if viewModel.isRefreshing, !viewModel.visibleSuggestions.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Refreshing suggestions…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                contentSection
            }
            .padding(16)
            .padding(.top, 30)
        }
        .navigationTitle("Suggestions")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: chosenDate) {
            await viewModel.load(for: chosenDate)
        }
        .task {
            await nutritionRepository.loadIfNeeded()
        }
        .refreshable {
            await viewModel.refreshCurrentDate()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active, isVisible else { return }
            Task {
                await viewModel.refreshCurrentDate()
            }
        }
    }

    @ViewBuilder
    private var nutritionProfileSection: some View {
        NavigationLink {
            NutritionProfileView {
                await viewModel.refreshCurrentDate()
            }
        } label: {
            NutritionProfileSummaryCard(repository: nutritionRepository)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var metricsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Today’s Nutrition Progress")
                .font(.headline)

            HStack(alignment: .top, spacing: 14) {
                MetricCard(
                    title: "Consumed",
                    valueText: "\(viewModel.consumedCalories)",
                    subtitle: "Estimated calories marked as eaten"
                )
            }
        }
    }

    @ViewBuilder
    private var contentSection: some View {
        if case .failed(let message) = viewModel.state, viewModel.visibleSuggestions.isEmpty {
            messageCard(title: "Couldn’t Load Suggestions", message: message, systemImage: "wifi.slash")
        } else if let emptyMessage = viewModel.emptyStateMessage {
            messageCard(title: "No Suggestions Yet", message: emptyMessage, systemImage: "fork.knife.circle")
        } else if viewModel.shouldShowLoadingCard {
            loadingCard
        } else {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(viewModel.visibleSuggestions.enumerated()), id: \.element.id) { index, suggestion in
                    if viewModel.firstPastMealIndex == index {
                        suggestionsDivider(title: "Past Meals")
                    }

                    SuggestionMealCard(
                        suggestion: suggestion,
                        isConsumed: viewModel.isConsumed(suggestion),
                        canToggleConsumed: viewModel.canMarkMealsConsumed
                    ) {
                        viewModel.toggleConsumed(suggestion)
                    }
                }

                if let summary = viewModel.response?.summary, !summary.isEmpty {
                    SummaryCard(title: "Daily Summary", message: summary)
                }

                ForEach(viewModel.response?.warnings ?? [], id: \.self) { warning in
                    SummaryCard(title: "Heads Up", message: warning, tint: .orange)
                }
            }
        }
    }

    private var loadingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProgressView()
            Text("Building meal suggestions for \(formattedDateLabel).")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func messageCard(title: String, message: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func suggestionsDivider(title: String) -> some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(Color.secondary.opacity(0.25))
                .frame(height: 1)

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .fixedSize()

            Rectangle()
                .fill(Color.secondary.opacity(0.25))
                .frame(height: 1)
        }
        .padding(.vertical, 4)
    }

    private var formattedDateLabel: String {
        guard let date = SuggestionsView.dateFormatter.date(from: chosenDate) else {
            return chosenDate
        }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private struct SuggestionMealCard: View {
    let suggestion: MealSuggestion
    let isConsumed: Bool
    let canToggleConsumed: Bool
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(suggestion.meal)
                        .font(.title3.weight(.semibold))
                    Text(suggestion.venue)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
                
                Button(action: action) {
                    Text(buttonTitle)
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.glassProminent)
                .tint(buttonTint)
                .disabled(!canToggleConsumed)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(suggestion.items, id: \.self) { item in
                    Label(item, systemImage: "fork.knife")
                        .font(.subheadline)
                }
            }

            HStack(spacing: 10) {
                if let calories = suggestion.estimatedCalories {
                    nutritionChip(title: "Calories", value: "\(calories)")
                }
                if let protein = suggestion.estimatedProteinG {
                    nutritionChip(title: "Protein", value: "\(protein)g")
                }
                if let carbs = suggestion.estimatedCarbsG {
                    nutritionChip(title: "Carbs", value: "\(carbs)g")
                }
                if let fat = suggestion.estimatedFatG {
                    nutritionChip(title: "Fat", value: "\(fat)g")
                }
            }

            Text(suggestion.rationale)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let caution = suggestion.optionalCaution, !caution.isEmpty {
                Text(caution)
                    .italic()
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private func nutritionChip(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var buttonTitle: String {
        if !canToggleConsumed {
            return "Future Meal"
        }
        return isConsumed ? "Consumed" : "Mark Consumed"
    }

    private var buttonTint: Color {
        if !canToggleConsumed {
            return .secondary
        }
        return isConsumed ? .green : .accentColor
    }
}

private struct MetricCard: View {
    let title: String
    let valueText: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            
            Text(valueText)
                .font(.title2.weight(.semibold))
                .contentTransition(.numericText())
            
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

private struct ProgressRingCard: View {
    let title: String
    let valueText: String
    let subtitle: String
    let progress: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .stroke(Color.primary.opacity(0.08), lineWidth: 12)

                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            AngularGradient(
                                colors: [.orange, .pink, .accentColor],
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 12, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))

                    Text(valueText)
                        .font(.title3.weight(.bold))
                }
                .frame(width: 88, height: 88)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

private struct SummaryCard: View {
    let title: String
    let message: String
    var tint: Color = .accentColor

    var bodyView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    var body: some View {
        bodyView
    }
}

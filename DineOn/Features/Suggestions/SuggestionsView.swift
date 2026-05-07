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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                metricsSection

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
        }
        .navigationTitle("Suggestions")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: chosenDate) {
            await viewModel.load(for: chosenDate)
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
    private var metricsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(viewModel.isTodaySelected ? "Today’s Nutrition Progress" : "Planned Nutrition Progress")
                .font(.headline)

            HStack(alignment: .top, spacing: 14) {
                if viewModel.isTodaySelected,
                   let activeCalories = viewModel.activeCaloriesToday,
                   let targetCalories = viewModel.dailyCalorieTarget,
                   targetCalories > 0 {
                    ProgressRingCard(
                        title: "Active Burn",
                        valueText: "\(activeCalories)",
                        subtitle: "of \(targetCalories) target",
                        progress: min(Double(activeCalories) / Double(targetCalories), 1.0)
                    )
                } else {
                    MetricCard(
                        title: "Daily Target",
                        valueText: viewModel.dailyCalorieTarget.map(String.init) ?? "Unavailable",
                        subtitle: viewModel.isTodaySelected ? "Connect HealthKit or save a nutrition profile." : "Used to score this date's suggestions."
                    )
                }

                VStack(spacing: 12) {
                    MetricCard(
                        title: "Consumed",
                        valueText: "\(viewModel.consumedCalories)",
                        subtitle: "Estimated calories marked as eaten"
                    )

                    MetricCard(
                        title: "Recommended Meals",
                        valueText: "\(viewModel.visibleSuggestions.count)",
                        subtitle: "Visible meals for this date"
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var contentSection: some View {
        if case .failed(let message) = viewModel.state, viewModel.visibleSuggestions.isEmpty {
            messageCard(title: "Couldn’t Load Suggestions", message: message, systemImage: "wifi.slash")
        } else if case .empty(let message) = viewModel.state, viewModel.visibleSuggestions.isEmpty {
            messageCard(title: "No Suggestions Yet", message: message, systemImage: "fork.knife.circle")
        } else if viewModel.visibleSuggestions.isEmpty {
            loadingCard
        } else {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(viewModel.visibleSuggestions) { suggestion in
                    SuggestionMealCard(
                        suggestion: suggestion,
                        isConsumed: viewModel.isConsumed(suggestion)
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

                Text(isConsumed ? "Consumed" : "Suggested")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(isConsumed ? Color.green.opacity(0.18) : Color.accentColor.opacity(0.14), in: Capsule())
                    .foregroundStyle(isConsumed ? .green : .accentColor)
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
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }

            Button(action: action) {
                Text(isConsumed ? "Mark as Not Consumed" : "Mark as Consumed")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(isConsumed ? Color.green.opacity(0.18) : Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
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
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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

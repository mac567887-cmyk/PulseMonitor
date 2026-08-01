import SwiftUI

/// Auto Optimizer.
///
/// Produces a ranked list of changes and performs one only when the user asks.
/// Anything that closes an application or touches files is marked destructive
/// and requires a confirmation step.
public struct OptimizerView: View {
    @Bindable var viewModel: OptimizerViewModel
    @State private var pendingConfirmation: OptimizationSuggestion?

    public init(viewModel: OptimizerViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.gridSpacing) {
                header

                if viewModel.isAnalyzing {
                    analyzingCard
                } else {
                    ForEach(viewModel.suggestions) { suggestion in
                        card(suggestion)
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.97).combined(with: .opacity),
                                removal: .opacity
                            ))
                    }
                }
            }
            .padding(DesignTokens.sectionSpacing)
            .animation(DesignTokens.Motion.standard, value: viewModel.suggestions)
            .animation(DesignTokens.Motion.standard, value: viewModel.isAnalyzing)
        }
        .background(AmbientBackdrop())
        .navigationTitle("Optimizer")
        .task {
            if viewModel.suggestions.isEmpty {
                await viewModel.analyze()
            }
        }
        .confirmationDialog(
            pendingConfirmation?.actionLabel ?? "Confirm",
            isPresented: Binding(
                get: { pendingConfirmation != nil },
                set: { if !$0 { pendingConfirmation = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let pending = pendingConfirmation {
                Button(pending.actionLabel ?? "Continue", role: .destructive) {
                    viewModel.perform(pending)
                    pendingConfirmation = nil
                }
            }
            Button("Cancel", role: .cancel) { pendingConfirmation = nil }
        } message: {
            Text("Save any open work first. This cannot be undone by PulseMonitor.")
        }
        .alert(
            "That action did not complete",
            isPresented: Binding(
                get: { viewModel.actionError != nil },
                set: { if !$0 { viewModel.dismissError() } }
            )
        ) {
            Button("OK") { viewModel.dismissError() }
        } message: {
            Text(viewModel.actionError ?? "")
        }
    }

    private var header: some View {
        GlassSection(title: "Auto Optimizer", systemImage: "wand.and.stars") {
            VStack(alignment: .leading, spacing: 10) {
                Text("PulseMonitor inspects CPU, memory, storage, thermals and network, then suggests changes ranked by how much difference they would make.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Label("Nothing here runs on its own. Every action needs your confirmation, and nothing is ever deleted.", systemImage: "hand.raised.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Button {
                        Task { await viewModel.analyze() }
                    } label: {
                        Label("Analyze Again", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isAnalyzing)

                    if let lastRun = viewModel.lastRun {
                        Text("Last run \(lastRun.formatted(date: .omitted, time: .standard))")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    private var analyzingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Analyzing your system…").font(.headline)
            }
            ShimmerPlaceholder(height: 16)
            ShimmerPlaceholder(height: 16)
            ShimmerPlaceholder(height: 16)
        }
        .glassCard()
    }

    private func card(_ suggestion: OptimizationSuggestion) -> some View {
        let isDone = viewModel.completed.contains(suggestion.id)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                impactBadge(suggestion.impact)
                Text(suggestion.title)
                    .font(.headline)
                    .strikethrough(isDone, color: .secondary)
                Spacer(minLength: 8)
                if isDone {
                    Label("Done", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .labelStyle(.titleAndIcon)
                }
            }

            Text(suggestion.detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let label = suggestion.actionLabel, !isDone {
                Button {
                    if suggestion.isDestructive {
                        pendingConfirmation = suggestion
                    } else {
                        viewModel.perform(suggestion)
                    }
                } label: {
                    Label(label, systemImage: suggestion.isDestructive ? "exclamationmark.triangle" : "arrow.right.circle")
                }
                .buttonStyle(.bordered)
                .tint(suggestion.isDestructive ? .orange : .accentColor)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .opacity(isDone ? 0.6 : 1)
    }

    private func impactBadge(_ impact: OptimizationSuggestion.Impact) -> some View {
        let tint: Color = switch impact {
        case .high: .red
        case .medium: .orange
        case .low: .secondary
        }

        return Text(impact.displayName)
            .font(.caption2.weight(.semibold))
            .textCase(.uppercase)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(tint.opacity(0.18)))
            .foregroundStyle(tint)
    }
}

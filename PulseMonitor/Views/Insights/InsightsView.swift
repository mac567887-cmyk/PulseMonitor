import SwiftUI

/// Smart Insights.
///
/// Reads a window of recorded samples and states what was measured. When the
/// window holds too few samples to support a claim, the view says so instead of
/// producing a weaker version of the same insight.
public struct InsightsView: View {
    @Bindable var viewModel: InsightsViewModel

    public init(viewModel: InsightsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.gridSpacing) {
                header

                if viewModel.isLoading {
                    loadingCard
                } else if viewModel.insights.isEmpty {
                    emptyCard
                } else {
                    ForEach(viewModel.insights) { insight in
                        card(insight)
                    }
                }
            }
            .padding(DesignTokens.sectionSpacing)
            .animation(DesignTokens.Motion.standard, value: viewModel.insights)
        }
        .background(AmbientBackdrop())
        .navigationTitle("Insights")
        .task { await viewModel.refresh() }
    }

    private var header: some View {
        GlassSection(title: "Smart Insights", systemImage: "sparkles") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Observations drawn from what PulseMonitor recorded, not from the current instant. Each one names the measurement behind it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Picker("Window", selection: $viewModel.window) {
                    ForEach(InsightsViewModel.WindowLength.allCases) { window in
                        Text(window.displayName).tag(window)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: viewModel.window) { _, _ in
                    Task { await viewModel.refresh() }
                }

                HStack {
                    Text("\(viewModel.sampleCount) samples covering \(Self.duration(viewModel.coveredInterval))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button {
                        Task { await viewModel.refresh() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private var loadingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            ShimmerPlaceholder(height: 18)
            ShimmerPlaceholder(height: 14)
            ShimmerPlaceholder(height: 14)
        }
        .glassCard()
    }

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Not enough recorded yet", systemImage: "hourglass")
                .font(.headline)
            Text(viewModel.sampleCount < 30
                 ? "PulseMonitor needs at least thirty samples before it will draw a conclusion. Leave it running for about half a minute and check back."
                 : "Nothing in this window stands out. CPU, memory, thermals, battery and storage all stayed within ordinary ranges.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func card(_ insight: Insight) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: insight.kind.symbol)
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 26)
                Text(insight.headline)
                    .font(.headline)
                Spacer(minLength: 8)
                confidenceBadge(insight.confidence)
            }

            Text(insight.body)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func confidenceBadge(_ confidence: Double) -> some View {
        Text("\(Int(confidence * 100))% confident")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.primary.opacity(0.06)))
    }

    private static func duration(_ interval: TimeInterval) -> String {
        guard interval > 0 else { return "no time yet" }
        if interval < 90 { return "\(Int(interval)) seconds" }
        return "\(Int(interval / 60)) minutes"
    }
}

import SwiftUI
import Charts

/// Benchmark suite with score history.
///
/// Scores come from timing real work, so they vary with what else the machine is
/// doing. The view says so rather than presenting a single run as definitive.
public struct BenchmarkView: View {
    @Bindable var viewModel: BenchmarkViewModel
    @State private var selectedKind: BenchmarkKind?
    @State private var historyPoints: [BenchmarkResult] = []

    public init(viewModel: BenchmarkViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.gridSpacing) {
                header

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 260, maximum: 400), spacing: DesignTokens.gridSpacing)],
                    spacing: DesignTokens.gridSpacing
                ) {
                    ForEach(BenchmarkKind.allCases) { kind in
                        card(for: kind)
                    }
                }

                if let selectedKind, historyPoints.count > 1 {
                    historyChart(for: selectedKind)
                }
            }
            .padding(DesignTokens.sectionSpacing)
        }
        .background(AmbientBackdrop())
        .navigationTitle("Benchmarks")
        .task { await viewModel.load() }
    }

    private var header: some View {
        GlassSection(title: "Benchmark Suite", systemImage: "speedometer") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Each test times real work: arithmetic kernels for CPU, large buffer copies for memory, flushed file I/O for disk, and a Metal compute dispatch for GPU.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Close other applications before running. Scores drop when the machine is busy or thermally throttled, which is a real result rather than an error.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Button {
                        Task { await viewModel.runAll() }
                    } label: {
                        Label("Run All", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.running != nil)

                    Button("Clear History") {
                        Task { await viewModel.clear() }
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.running != nil || viewModel.results.isEmpty)

                    if let running = viewModel.running {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Running \(running.displayName)…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .transition(.opacity)
                    }
                }
                .animation(DesignTokens.Motion.standard, value: viewModel.running)
            }
        }
    }

    private func card(for kind: BenchmarkKind) -> some View {
        let result = viewModel.latest[kind]
        let delta = viewModel.deltas[kind]
        let isRunning = viewModel.running == kind
        let isSelected = selectedKind == kind

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(kind.displayName, systemImage: kind.symbol)
                    .font(.headline)
                Spacer()
                if isRunning {
                    ProgressView().controlSize(.small)
                }
            }

            if isRunning {
                ShimmerPlaceholder(height: 30)
                ShimmerPlaceholder(height: 12)
            } else if let result {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(format(result.score))
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text(result.unit)
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    if let delta, abs(delta) >= 1 {
                        Label(
                            String(format: "%+.0f%%", delta),
                            systemImage: delta > 0 ? "arrow.up.right" : "arrow.down.right"
                        )
                        .font(.caption.weight(.medium))
                        .foregroundStyle(delta > 0 ? .green : .orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill((delta > 0 ? Color.green : Color.orange).opacity(0.15))
                        )
                    }
                }

                Text(result.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(result.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                Text("Not run yet")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(height: 30)
            }

            HStack {
                Button {
                    Task { await viewModel.run(kind) }
                } label: {
                    Label("Run", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.running != nil)

                Button {
                    Task { await select(kind) }
                } label: {
                    Image(systemName: "chart.xyaxis.line")
                }
                .buttonStyle(.bordered)
                .help("Show score history")
            }
        }
        .glassCard(isElevated: isSelected)
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: DesignTokens.cardCornerRadius, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 1.5)
            }
        }
        .animation(DesignTokens.Motion.standard, value: isSelected)
        .animation(DesignTokens.Motion.standard, value: isRunning)
    }

    private func historyChart(for kind: BenchmarkKind) -> some View {
        GlassSection(title: "\(kind.displayName) History", systemImage: "chart.xyaxis.line") {
            Chart(historyPoints) { point in
                LineMark(
                    x: .value("Run", point.date),
                    y: .value("Score", point.score)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(Color.accentColor)

                PointMark(
                    x: .value("Run", point.date),
                    y: .value("Score", point.score)
                )
                .foregroundStyle(Color.accentColor)
                .symbolSize(40)

                AreaMark(
                    x: .value("Run", point.date),
                    y: .value("Score", point.score)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.accentColor.opacity(0.28), .clear],
                        startPoint: .top, endPoint: .bottom
                    )
                )
            }
            .chartYAxisLabel(historyPoints.first?.unit ?? "")
            .frame(height: 200)
        } accessory: {
            Button {
                withAnimation(DesignTokens.Motion.standard) { selectedKind = nil }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private func select(_ kind: BenchmarkKind) async {
        let points = await viewModel.history(for: kind)
        withAnimation(DesignTokens.Motion.standard) {
            historyPoints = points
            selectedKind = kind
        }
    }

    private func format(_ score: Double) -> String {
        score >= 100 ? String(format: "%.0f", score) : String(format: "%.1f", score)
    }
}

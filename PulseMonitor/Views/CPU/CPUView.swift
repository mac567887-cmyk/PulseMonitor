import SwiftUI
import Charts

public struct CPUView: View {
    @Bindable var viewModel: CPUViewModel

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SectionHeader("CPU", subtitle: viewModel.metrics?.brand)
                summary
                if let metrics = viewModel.metrics {
                    CoreHeatmapView(values: metrics.perCoreUsage, columns: min(8, max(4, metrics.logicalCoreCount / 2)))
                    peSplit(metrics)
                }
                timeline
                topProcesses
            }
            .padding(24)
        }
        .background(AmbientBackground())
    }

    private var summary: some View {
        let m = viewModel.metrics
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
            stat("Total", Formatters.percent(m?.totalUsage ?? 0))
            stat("User", Formatters.percent(m?.userUsage ?? 0))
            stat("System", Formatters.percent(m?.systemUsage ?? 0))
            stat("Idle", Formatters.percent(m?.idleUsage ?? 0))
            stat("Load 1/5/15", String(format: "%.2f / %.2f / %.2f", m?.loadAverage1 ?? 0, m?.loadAverage5 ?? 0, m?.loadAverage15 ?? 0))
            stat("Freq", Formatters.mhz(m?.currentFrequencyMHz))
            stat("Threads", "\(m?.threadCount ?? 0)")
            stat("Trend", "\(viewModel.trend.symbol) \(viewModel.trend.rawValue)")
        }
    }

    private func peSplit(_ metrics: CPUMetrics) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading) {
                Text("Performance Cores (\(metrics.performanceCoreCount))").font(.headline)
                CoreHeatmapView(values: metrics.performanceCoreUsage, columns: 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading) {
                Text("Efficiency Cores (\(metrics.efficiencyCoreCount))").font(.headline)
                CoreHeatmapView(values: metrics.efficiencyCoreUsage, columns: 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var timeline: some View {
        VStack(alignment: .leading) {
            Text("Timeline").font(.headline)
            Chart {
                ForEach(Array(viewModel.history.enumerated()), id: \.offset) { i, v in
                    LineMark(x: .value("t", i), y: .value("cpu", v))
                        .foregroundStyle(.blue)
                    AreaMark(x: .value("t", i), y: .value("cpu", v))
                        .foregroundStyle(.blue.opacity(0.12))
                }
            }
            .frame(height: 180)
            .chartYScale(domain: 0...100)
        }
    }

    private var topProcesses: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Top CPU Processes").font(.headline)
            ForEach(viewModel.topProcesses) { proc in
                HStack {
                    Text(proc.name).lineLimit(1)
                    Spacer()
                    Text(Formatters.percent(proc.cpuPercent, digits: 1))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

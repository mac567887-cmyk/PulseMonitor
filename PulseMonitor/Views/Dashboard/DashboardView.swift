import SwiftUI

public struct DashboardView: View {
    @Bindable var viewModel: DashboardViewModel
    @Bindable var analysisViewModel: AnalysisViewModel

    /// Supplied only by the main window so the developer console can be shown
    /// there without every torn-off dashboard duplicating the SMC polling.
    var developerConsole: (collector: MetricsCollector, controlCenter: ControlCenterViewModel)?
    var developerModeEnabled = false

    public init(
        viewModel: DashboardViewModel,
        analysisViewModel: AnalysisViewModel,
        developerConsole: (collector: MetricsCollector, controlCenter: ControlCenterViewModel)? = nil,
        developerModeEnabled: Bool = false
    ) {
        self.viewModel = viewModel
        self.analysisViewModel = analysisViewModel
        self.developerConsole = developerConsole
        self.developerModeEnabled = developerModeEnabled
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                insightBanner
                cardGrid

                if developerModeEnabled, let console = developerConsole {
                    DeveloperConsole(collector: console.collector, controlCenter: console.controlCenter)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .padding(24)
            .animation(DesignTokens.Motion.standard, value: developerModeEnabled)
        }
        .background(AmbientBackground())
    }

    private var header: some View {
        HStack(alignment: .top) {
            BrandMark(size: 56)
            VStack(alignment: .leading, spacing: 6) {
                Text("PulseMonitor")
                    .font(.largeTitle.weight(.bold))
                Text("Intelligent performance diagnostics")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("Health")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(String(format: "%.0f", viewModel.healthScore))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(healthColor)
            }
        }
    }

    private var insightBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Why is this Mac slow?", systemImage: "waveform.path.ecg")
                .font(.headline)
            Text(viewModel.narrative)
                .font(.body)
                .foregroundStyle(.primary.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)

            if let findings = analysisViewModel.report?.findings.prefix(3), !findings.isEmpty {
                Divider().opacity(0.3)
                ForEach(Array(findings)) { finding in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(severityColor(finding.severity))
                            .frame(width: 8, height: 8)
                            .padding(.top, 6)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(finding.title).font(.subheadline.weight(.semibold))
                            Text(finding.summary).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }

    private var cardGrid: some View {
        let m = viewModel.metrics
        let columns = [GridItem(.adaptive(minimum: 220), spacing: 14)]
        return LazyVGrid(columns: columns, spacing: 14) {
            MetricCard(
                title: "CPU",
                valueText: Formatters.percent(m?.cpu.totalUsage ?? 0),
                subtitle: m?.cpu.brand ?? "Sampling…",
                history: viewModel.collector.cpuHistory,
                trend: TrendCalculator.trend(of: viewModel.collector.cpuHistory),
                status: viewModel.status(for: m?.cpu.totalUsage ?? 0),
                predictionText: prediction(viewModel.collector.cpuHistory, unit: "%"),
                accent: .blue
            )
            MetricCard(
                title: "GPU",
                valueText: Formatters.percent(m?.gpu.utilization ?? 0),
                subtitle: m?.gpu.deviceName ?? "GPU",
                history: viewModel.collector.gpuHistory,
                trend: TrendCalculator.trend(of: viewModel.collector.gpuHistory),
                status: viewModel.status(for: m?.gpu.utilization ?? 0),
                accent: .purple
            )
            MetricCard(
                title: "Memory",
                valueText: Formatters.percent(m?.memory.usagePercent ?? 0),
                subtitle: "Pressure: \(m?.memory.pressure.displayName ?? "—")",
                history: viewModel.collector.memoryHistory,
                trend: TrendCalculator.trend(of: viewModel.collector.memoryHistory),
                status: memoryStatus(m?.memory.pressure),
                accent: .teal
            )
            MetricCard(
                title: "Swap",
                valueText: Formatters.bytes(m?.memory.swapUsedBytes ?? 0),
                subtitle: "Compressed \(Formatters.bytes(m?.memory.compressedBytes ?? 0))",
                history: viewModel.collector.memoryHistory,
                trend: .stable,
                status: (m?.memory.swapUsedBytes ?? 0) > 1_073_741_824 ? .warning : .ok,
                accent: .mint
            )
            MetricCard(
                title: "Network ↓",
                valueText: Formatters.bytesPerSecond(m?.network.bytesInPerSec ?? 0),
                subtitle: "↑ \(Formatters.bytesPerSecond(m?.network.bytesOutPerSec ?? 0))",
                history: viewModel.collector.networkInHistory,
                trend: TrendCalculator.trend(of: viewModel.collector.networkInHistory),
                status: .ok,
                accent: .cyan
            )
            MetricCard(
                title: "Thermal",
                valueText: m?.thermal.thermalState.displayName ?? "—",
                subtitle: Formatters.celsius(m?.thermal.cpuTemperatureC ?? m?.thermal.batteryTemperatureC),
                history: viewModel.collector.temperatureHistory,
                trend: TrendCalculator.trend(of: viewModel.collector.temperatureHistory),
                status: thermalStatus(m?.thermal.thermalState),
                accent: .orange
            )
            MetricCard(
                title: "Disk",
                valueText: rootUsedText(m),
                subtitle: "R \(Formatters.bytesPerSecond(m?.storage.readBytesPerSec ?? 0)) · W \(Formatters.bytesPerSecond(m?.storage.writeBytesPerSec ?? 0))",
                history: [],
                trend: .stable,
                status: rootStatus(m),
                accent: .indigo
            )
            MetricCard(
                title: "Battery",
                valueText: batteryText(m),
                subtitle: batterySubtitle(m),
                history: [],
                trend: .stable,
                status: .ok,
                accent: .green
            )
            MetricCard(
                title: "Power",
                valueText: Formatters.watts(m?.power.totalSystemWatts == 0 ? nil : m?.power.totalSystemWatts),
                subtitle: m?.power.isEstimated == true ? "Estimated" : "Measured",
                history: [],
                trend: .stable,
                status: .ok,
                accent: .yellow
            )
            MetricCard(
                title: "Uptime",
                valueText: Formatters.uptime(m?.uptime ?? 0),
                subtitle: "Since last boot",
                history: [],
                trend: .stable,
                status: .ok,
                accent: .secondary
            )
        }
    }

    private var healthColor: Color {
        switch viewModel.healthScore {
        case 80...: .green
        case 60..<80: .orange
        default: .red
        }
    }

    private func prediction(_ values: [Double], unit: String) -> String? {
        guard let next = TrendCalculator.predictNext(of: values) else { return nil }
        return String(format: "Predicted next: %.0f%@", next, unit)
    }

    private func memoryStatus(_ pressure: MemoryMetrics.MemoryPressure?) -> MetricStatus {
        switch pressure {
        case .critical: .critical
        case .warning: .warning
        default: .ok
        }
    }

    private func thermalStatus(_ state: ThermalMetrics.ThermalState?) -> MetricStatus {
        switch state {
        case .critical, .serious: .critical
        case .fair: .warning
        default: .ok
        }
    }

    private func severityColor(_ severity: BottleneckFinding.Severity) -> Color {
        switch severity {
        case .info: .blue
        case .warning: .orange
        case .critical: .red
        }
    }

    private func rootUsedText(_ m: SystemMetrics?) -> String {
        guard let root = m?.storage.volumes.first(where: \.isRoot) else { return "—" }
        return Formatters.percent(root.usedPercent)
    }

    private func rootStatus(_ m: SystemMetrics?) -> MetricStatus {
        guard let root = m?.storage.volumes.first(where: \.isRoot) else { return .ok }
        return viewModel.status(for: root.usedPercent, warning: 85, critical: 95)
    }

    private func batteryText(_ m: SystemMetrics?) -> String {
        guard let b = m?.battery, b.isPresent, let charge = b.chargePercent else { return "AC Power" }
        return Formatters.percent(charge)
    }

    private func batterySubtitle(_ m: SystemMetrics?) -> String {
        guard let b = m?.battery, b.isPresent else { return "Desktop / no battery" }
        if b.isCharging { return "Charging · \(Formatters.watts(b.wattage))" }
        guard let health = b.healthPercent else { return b.powerSource.rawValue }
        return "\(b.powerSource.rawValue) · Health \(Formatters.percent(health))"
    }
}

public struct AmbientBackground: View {
    public var body: some View {
        LinearGradient(
            colors: [
                Color(nsColor: .windowBackgroundColor),
                Color.blue.opacity(0.07),
                Color.teal.opacity(0.05)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

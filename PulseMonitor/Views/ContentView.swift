import SwiftUI

public enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case dashboard, cpu, gpu, memory, thermal, storage, network, battery, processes, history, games, analysis, reports, settings

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .cpu: "CPU"
        case .gpu: "GPU"
        case .memory: "Memory"
        case .thermal: "Thermal"
        case .storage: "Storage"
        case .network: "Network"
        case .battery: "Battery"
        case .processes: "Processes"
        case .history: "History"
        case .games: "Games"
        case .analysis: "Analysis"
        case .reports: "Reports"
        case .settings: "Settings"
        }
    }

    public var icon: String {
        switch self {
        case .dashboard: "gauge.with.dots.needle.67percent"
        case .cpu: "cpu"
        case .gpu: "cube"
        case .memory: "memorychip"
        case .thermal: "thermometer.medium"
        case .storage: "internaldrive"
        case .network: "network"
        case .battery: "battery.100"
        case .processes: "list.bullet.rectangle"
        case .history: "clock.arrow.circlepath"
        case .games: "gamecontroller"
        case .analysis: "stethoscope"
        case .reports: "doc.richtext"
        case .settings: "gearshape"
        }
    }
}

public struct ContentView: View {
    @Bindable var container: AppContainer
    @State private var selection: SidebarItem? = .dashboard

    public var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { item in
                Label(item.title, systemImage: item.icon)
                    .tag(item)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
            .listStyle(.sidebar)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .preferredColorScheme(container.settings.appearance.colorScheme)
    }

    @ViewBuilder
    private var detail: some View {
        switch selection ?? .dashboard {
        case .dashboard:
            DashboardView(viewModel: container.dashboardViewModel, analysisViewModel: container.analysisViewModel)
        case .cpu:
            CPUView(viewModel: container.cpuViewModel)
        case .gpu:
            GPUView(viewModel: container.gpuViewModel)
        case .memory:
            MemoryView(viewModel: container.memoryViewModel)
        case .thermal:
            ThermalView(viewModel: container.thermalViewModel)
        case .storage:
            StorageView(viewModel: container.storageViewModel)
        case .network:
            NetworkView(viewModel: container.networkViewModel)
        case .battery:
            BatteryView(viewModel: container.batteryViewModel)
        case .processes:
            ProcessExplorerView(viewModel: container.processViewModel)
        case .history:
            HistoryView(viewModel: container.historyViewModel)
        case .games:
            GamesView(viewModel: container.gamesViewModel)
        case .analysis:
            AnalysisDetailView(viewModel: container.analysisViewModel)
        case .reports:
            ReportsView(container: container)
        case .settings:
            SettingsView(viewModel: container.settingsViewModel)
        }
    }
}

public struct AnalysisDetailView: View {
    @Bindable var viewModel: AnalysisViewModel

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader("AI Analysis Engine", subtitle: "Rule-based bottleneck detection — fully on-device")
                Text(viewModel.report?.narrative ?? "Waiting for samples…")
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                ForEach(viewModel.report?.findings ?? []) { finding in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(finding.title).font(.headline)
                            Spacer()
                            Text(finding.severity.rawValue.uppercased())
                                .font(.caption2.weight(.bold))
                                .padding(5)
                                .background(severityColor(finding.severity).opacity(0.15), in: Capsule())
                                .foregroundStyle(severityColor(finding.severity))
                        }
                        Text(finding.summary)
                        Text(finding.detail).font(.callout).foregroundStyle(.secondary)
                        if !finding.relatedProcesses.isEmpty {
                            Text("Related: \(finding.relatedProcesses.joined(separator: ", "))")
                                .font(.caption)
                        }
                        ForEach(finding.recommendations, id: \.self) { rec in
                            Label(rec, systemImage: "checkmark.circle")
                                .font(.callout)
                        }
                    }
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .padding(24)
        }
        .background(AmbientBackground())
    }

    private func severityColor(_ severity: BottleneckFinding.Severity) -> Color {
        switch severity {
        case .info: .blue
        case .warning: .orange
        case .critical: .red
        }
    }
}

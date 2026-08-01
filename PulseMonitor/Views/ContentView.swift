import SwiftUI

/// Every module the app can show, in sidebar order.
public enum SidebarItem: String, CaseIterable, Identifiable, Hashable, Codable {
    case dashboard, insights, analysis
    case cpu, gpu, memory, thermal, storage, network, battery
    case processes, applications
    case controlCenter, fans, profiles, optimizer
    case benchmarks, systemMap, timeline, history, logs
    case games, reports, settings

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .insights: "Insights"
        case .analysis: "Analysis"
        case .cpu: "CPU"
        case .gpu: "GPU"
        case .memory: "Memory"
        case .thermal: "Thermal"
        case .storage: "Storage"
        case .network: "Network"
        case .battery: "Battery"
        case .processes: "Processes"
        case .applications: "Applications"
        case .controlCenter: "Control Center"
        case .fans: "Fans & Sensors"
        case .profiles: "Profiles"
        case .optimizer: "Optimizer"
        case .benchmarks: "Benchmarks"
        case .systemMap: "System Map"
        case .timeline: "Timeline"
        case .history: "History"
        case .logs: "Logs"
        case .games: "Games"
        case .reports: "Reports"
        case .settings: "Settings"
        }
    }

    public var icon: String {
        switch self {
        case .dashboard: "gauge.with.dots.needle.67percent"
        case .insights: "sparkles"
        case .analysis: "stethoscope"
        case .cpu: "cpu"
        case .gpu: "cube"
        case .memory: "memorychip"
        case .thermal: "thermometer.medium"
        case .storage: "internaldrive"
        case .network: "network"
        case .battery: "battery.100"
        case .processes: "list.bullet.rectangle"
        case .applications: "square.grid.2x2"
        case .controlCenter: "switch.2"
        case .fans: "fan.fill"
        case .profiles: "slider.horizontal.3"
        case .optimizer: "wand.and.stars"
        case .benchmarks: "speedometer"
        case .systemMap: "point.3.connected.trianglepath.dotted"
        case .timeline: "clock.arrow.circlepath"
        case .history: "chart.xyaxis.line"
        case .logs: "doc.text.magnifyingglass"
        case .games: "gamecontroller"
        case .reports: "doc.richtext"
        case .settings: "gearshape"
        }
    }

    /// Sidebar grouping.
    public enum Section: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case hardware = "Hardware"
        case activity = "Activity"
        case control = "Control"
        case tools = "Tools"

        public var id: String { rawValue }

        public var items: [SidebarItem] {
            switch self {
            case .overview: [.dashboard, .insights, .analysis]
            case .hardware: [.cpu, .gpu, .memory, .thermal, .storage, .network, .battery]
            case .activity: [.processes, .applications, .games]
            case .control: [.controlCenter, .fans, .profiles, .optimizer]
            case .tools: [.benchmarks, .systemMap, .timeline, .history, .logs, .reports, .settings]
            }
        }
    }
}

/// Root split view.
public struct ContentView: View {
    @Bindable var container: AppContainer
    @State private var selection: SidebarItem? = .dashboard
    @Environment(\.openWindow) private var openWindow

    public init(container: AppContainer) {
        self.container = container
    }

    public var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            ModuleDetail(container: container, item: selection ?? .dashboard)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .toolbar { toolbarContent }
                // Re-running the transition on each selection keeps navigation
                // feeling responsive without animating the metric values inside.
                .transition(.opacity)
                .animation(DesignTokens.Motion.quick, value: selection)
        }
        .environment(\.theme, container.settings.theme)
        .tint(container.settings.theme.accent)
    }

    private var sidebar: some View {
        List(selection: $selection) {
            ForEach(SidebarItem.Section.allCases) { section in
                Section(section.rawValue) {
                    ForEach(section.items) { item in
                        Label(item.title, systemImage: item.icon)
                            .tag(item)
                            .contextMenu {
                                Button("Open in New Window") {
                                    openWindow(id: "module", value: item)
                                }
                            }
                    }
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 218, max: 280)
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) { profileFooter }
    }

    /// Persistent profile indicator so the active monitoring behaviour is never
    /// a mystery.
    private var profileFooter: some View {
        HStack(spacing: 7) {
            Image(systemName: container.settings.activeProfile.symbol)
                .foregroundStyle(container.settings.theme.accent)
            VStack(alignment: .leading, spacing: 0) {
                Text(container.settings.activeProfile.displayName)
                    .font(.caption.weight(.medium))
                Text(String(format: "%.1fs sampling", container.settings.refreshIntervalSeconds))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            Spacer()
            if container.settings.overlayEnabled {
                Image(systemName: "rectangle.on.rectangle.angled")
                    .font(.caption)
                    .foregroundStyle(container.settings.theme.accent)
                    .help("Performance overlay is visible")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Toggle(isOn: Binding(
                get: { container.settings.overlayEnabled },
                set: { container.settings.overlayEnabled = $0 }
            )) {
                Label("Overlay", systemImage: "rectangle.on.rectangle.angled")
            }
            .toggleStyle(.button)
            .help("Show the floating performance overlay")
        }

        ToolbarItem(placement: .primaryAction) {
            Menu {
                Picker("Profile", selection: Binding(
                    get: { container.settings.activeProfile },
                    set: { container.powerProfileService.apply($0) }
                )) {
                    ForEach(PowerProfile.Kind.allCases) { kind in
                        Label(kind.displayName, systemImage: kind.symbol).tag(kind)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Label("Profile", systemImage: container.settings.activeProfile.symbol)
            }
            .help("Switch power profile")
        }

        ToolbarItem(placement: .primaryAction) {
            Menu {
                Picker("Theme", selection: Binding(
                    get: { container.settings.theme },
                    set: { container.settings.theme = $0 }
                )) {
                    ForEach(Theme.allCases) { theme in
                        Text(theme.displayName).tag(theme)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Label("Theme", systemImage: "paintpalette")
            }
            .help("Change appearance")
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                if let item = selection {
                    openWindow(id: "module", value: item)
                }
            } label: {
                Label("New Window", systemImage: "macwindow.badge.plus")
            }
            .help("Open this module in its own window")
        }
    }
}

/// Resolves a sidebar item to its module view.
///
/// Shared by the main split view and every torn-off window so both routes stay
/// identical.
public struct ModuleDetail: View {
    let container: AppContainer
    let item: SidebarItem

    public init(container: AppContainer, item: SidebarItem) {
        self.container = container
        self.item = item
    }

    public var body: some View {
        switch item {
        case .dashboard:
            DashboardView(
                viewModel: container.dashboardViewModel,
                analysisViewModel: container.analysisViewModel,
                developerConsole: (container.metricsCollector, container.controlCenterViewModel),
                developerModeEnabled: container.settings.developerModeEnabled
            )
        case .insights:
            InsightsView(viewModel: container.insightsViewModel)
        case .analysis:
            AnalysisDetailView(viewModel: container.analysisViewModel)
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
        case .applications:
            AppManagerView(viewModel: container.appManagerViewModel)
        case .controlCenter:
            ControlCenterView(viewModel: container.controlCenterViewModel)
        case .fans:
            FanControlView(viewModel: container.controlCenterViewModel)
        case .profiles:
            ProfilesView(
                settings: container.settings,
                profileService: container.powerProfileService,
                automation: container.automationEngine
            )
        case .optimizer:
            OptimizerView(viewModel: container.optimizerViewModel)
        case .benchmarks:
            BenchmarkView(viewModel: container.benchmarkViewModel)
        case .systemMap:
            SystemMapView(
                collector: container.metricsCollector,
                host: container.controlCenterViewModel.host
            )
            .task { await container.controlCenterViewModel.load() }
        case .timeline:
            TimelineView(
                history: container.historyRepository,
                eventLog: container.eventLogService,
                settings: container.settings
            )
        case .history:
            HistoryView(viewModel: container.historyViewModel)
        case .logs:
            EventLogView(eventLog: container.eventLogService)
        case .games:
            GamesView(viewModel: container.gamesViewModel)
        case .reports:
            ReportsView(container: container)
        case .settings:
            SettingsView(viewModel: container.settingsViewModel)
        }
    }
}

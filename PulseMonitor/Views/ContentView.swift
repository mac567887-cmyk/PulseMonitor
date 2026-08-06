import SwiftUI

/// Every module the app can show, in sidebar order.
public enum SidebarItem: String, CaseIterable, Identifiable, Hashable, Codable {
    case dashboard, insights, analysis, health, copilot, search
    case cpu, gpu, memory, thermal, storage, network, battery
    case processes, applications, widgets, games, gameLab
    case controlCenter, fans, profiles, optimizer, plugins, workspaces
    case benchmarks, systemMap, digitalTwin, hardwareDB
    case usbLab, bluetoothLab, displayLab, windowServer, developerLab
    case packages, snapshots, timeline, history, logs, logAnalyzer
    case menuBarStudio, webDashboard, reports, settings

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .insights: "Insights"
        case .analysis: "Analysis"
        case .health: "Health Score"
        case .copilot: "AI Copilot"
        case .search: "Search"
        case .cpu: "CPU"
        case .gpu: "GPU"
        case .memory: "Memory"
        case .thermal: "Thermal"
        case .storage: "Storage"
        case .network: "Network"
        case .battery: "Battery"
        case .processes: "Processes"
        case .applications: "Applications"
        case .widgets: "Widgets"
        case .games: "Games"
        case .gameLab: "Game Lab"
        case .controlCenter: "Control Center"
        case .fans: "Fans & Sensors"
        case .profiles: "Profiles"
        case .optimizer: "Optimizer"
        case .plugins: "Plugins"
        case .workspaces: "Workspaces"
        case .benchmarks: "Benchmarks"
        case .systemMap: "System Map"
        case .digitalTwin: "Digital Twin"
        case .hardwareDB: "Hardware DB"
        case .usbLab: "USB Devices"
        case .bluetoothLab: "Bluetooth Lab"
        case .displayLab: "Display Lab"
        case .windowServer: "WindowServer"
        case .developerLab: "Developer Lab"
        case .packages: "Packages"
        case .snapshots: "Snapshots"
        case .timeline: "Timeline"
        case .history: "History"
        case .logs: "Logs"
        case .logAnalyzer: "Log Analyzer"
        case .menuBarStudio: "Menu Bar Studio"
        case .webDashboard: "Web Dashboard"
        case .reports: "Reports"
        case .settings: "Settings"
        }
    }

    public var icon: String {
        switch self {
        case .dashboard: "gauge.with.dots.needle.67percent"
        case .insights: "sparkles"
        case .analysis: "stethoscope"
        case .health: "heart.text.square"
        case .copilot: "bubble.left.and.bubble.right"
        case .search: "magnifyingglass"
        case .cpu: "cpu"
        case .gpu: "cube"
        case .memory: "memorychip"
        case .thermal: "thermometer.medium"
        case .storage: "internaldrive"
        case .network: "network"
        case .battery: "battery.100"
        case .processes: "list.bullet.rectangle"
        case .applications: "square.grid.2x2"
        case .widgets: "rectangle.3.group"
        case .games: "gamecontroller"
        case .gameLab: "flag.checkered"
        case .controlCenter: "switch.2"
        case .fans: "fan.fill"
        case .profiles: "slider.horizontal.3"
        case .optimizer: "wand.and.stars"
        case .plugins: "puzzlepiece.extension"
        case .workspaces: "square.grid.3x3"
        case .benchmarks: "speedometer"
        case .systemMap: "point.3.connected.trianglepath.dotted"
        case .digitalTwin: "rotate.3d"
        case .hardwareDB: "shippingbox"
        case .usbLab: "cable.connector"
        case .bluetoothLab: "wave.3.right"
        case .displayLab: "display"
        case .windowServer: "macwindow"
        case .developerLab: "hammer"
        case .packages: "shippingbox.fill"
        case .snapshots: "camera.viewfinder"
        case .timeline: "clock.arrow.circlepath"
        case .history: "chart.xyaxis.line"
        case .logs: "doc.text.magnifyingglass"
        case .logAnalyzer: "waveform.path.ecg"
        case .menuBarStudio: "menubar.rectangle"
        case .webDashboard: "globe"
        case .reports: "doc.richtext"
        case .settings: "gearshape"
        }
    }

    public enum Section: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case hardware = "Hardware"
        case activity = "Activity"
        case labs = "Labs"
        case control = "Control"
        case tools = "Tools"

        public var id: String { rawValue }

        public var items: [SidebarItem] {
            switch self {
            case .overview: [.dashboard, .health, .copilot, .insights, .analysis, .search, .widgets]
            case .hardware: [.cpu, .gpu, .memory, .thermal, .storage, .network, .battery, .hardwareDB]
            case .activity: [.processes, .applications, .games, .gameLab]
            case .labs: [.digitalTwin, .systemMap, .usbLab, .bluetoothLab, .displayLab, .windowServer, .developerLab]
            case .control: [.controlCenter, .fans, .profiles, .optimizer, .workspaces, .plugins, .menuBarStudio]
            case .tools: [.snapshots, .timeline, .history, .logs, .logAnalyzer, .packages, .benchmarks, .webDashboard, .reports, .settings]
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
                .transition(.opacity)
                .animation(DesignTokens.Motion.quick, value: selection)
        }
        .environment(\.theme, container.settings.theme)
        .tint(container.settings.theme.accent)
        .searchable(text: Bindable(container.v3).searchQuery, prompt: "Search PulseMonitor")
        .onChange(of: container.v3.searchQuery) { _, _ in
            container.v3.updateSearch(
                processes: container.metricsCollector.latestProcesses,
                events: container.eventLogService.events
            )
            if !container.v3.searchQuery.isEmpty {
                selection = .search
            }
        }
        .onChange(of: container.metricsCollector.latestMetrics?.timestamp) { _, _ in
            refreshV3()
        }
        .task {
            refreshV3()
            await container.v3.refreshHardware()
            container.v3.usb.refresh()
            container.v3.displays.refresh()
        }
    }

    private func refreshV3() {
        guard let metrics = container.metricsCollector.latestMetrics else { return }
        let processes = container.metricsCollector.latestProcesses
        let findings = container.metricsCollector.latestAnalysis?.findings ?? []
        let games = processes.filter(\.isGame)
        container.v3.tick(
            metrics: metrics,
            processes: processes,
            findings: findings,
            games: games,
            events: container.eventLogService.events
        )
        container.athena.tick(
            metrics: metrics,
            processes: processes,
            findings: findings,
            games: games,
            samples: container.metricsCollector.recentSamples,
            healthOverall: container.v3.health?.overall,
            settings: container.settings
        )
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
        .navigationSplitViewColumnWidth(min: 200, ideal: 228, max: 300)
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) { profileFooter }
    }

    private var profileFooter: some View {
        HStack(spacing: 8) {
            BrandMark(size: 28)
            VStack(alignment: .leading, spacing: 0) {
                Text(container.settings.activeProfile.displayName)
                    .font(.caption.weight(.medium))
                Text(String(format: "%.1fs · health %.0f",
                               container.settings.refreshIntervalSeconds,
                               container.v3.health?.overall ?? 100))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            Spacer()
            if container.settings.overlayEnabled {
                Image(systemName: "rectangle.on.rectangle.angled")
                    .font(.caption)
                    .foregroundStyle(container.settings.theme.accent)
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
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                if let item = selection {
                    openWindow(id: "module", value: item)
                }
            } label: {
                Label("New Window", systemImage: "macwindow.badge.plus")
            }
        }
    }
}

/// Resolves a sidebar item to its module view.
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
        case .health:
            HealthScoreView(report: container.v3.health, history: container.v3.healthHistory)
        case .copilot:
            AICopilotDashboard(
                athena: container.athena,
                health: container.v3.health,
                healthHistory: container.v3.healthHistory,
                legacyMessages: container.v3.copilotMessages,
                developerMode: container.settings.developerModeEnabled || container.settings.aiDeveloperReasoning
            )
        case .search:
            UniversalSearchView(
                query: Bindable(container.v3).searchQuery,
                hits: container.v3.searchHits,
                onOpen: { _ in }
            )
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
        case .widgets:
            WidgetBoardView(
                store: container.widgetBoardStore,
                collector: container.metricsCollector,
                pluginHost: container.pluginHost
            )
        case .games:
            GamesView(viewModel: container.gamesViewModel)
        case .gameLab:
            GameLabView(service: container.v3.gameLab)
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
        case .plugins:
            PluginsView(host: container.pluginHost)
        case .workspaces:
            WorkspacesView(
                store: container.v3.workspaces,
                settings: container.settings,
                profiles: container.powerProfileService,
                onApply: { _ in }
            )
        case .benchmarks:
            BenchmarkView(viewModel: container.benchmarkViewModel)
        case .systemMap:
            SystemMapView(
                collector: container.metricsCollector,
                host: container.controlCenterViewModel.host
            )
            .task { await container.controlCenterViewModel.load() }
        case .digitalTwin:
            DigitalTwinView(twin: container.v3.twin)
        case .hardwareDB:
            HardwareDatabaseView(inventory: container.v3.hardware) {
                Task { await container.v3.refreshHardware() }
            }
        case .usbLab:
            USBLabView(service: container.v3.usb)
        case .bluetoothLab:
            BluetoothLabView(service: container.v3.bluetooth)
        case .displayLab:
            DisplayLabView(service: container.v3.displays)
        case .windowServer:
            WindowServerLabView(processes: container.metricsCollector.latestProcesses)
        case .developerLab:
            DeveloperLabView(
                processes: container.metricsCollector.latestProcesses,
                metrics: container.metricsCollector.latestMetrics
            )
        case .packages:
            PackageManagerView(service: container.v3.packages)
        case .snapshots:
            SnapshotsView(service: container.v3.snapshots) {
                if let metrics = container.metricsCollector.latestMetrics {
                    container.v3.captureSnapshot(
                        metrics: metrics,
                        analysis: container.metricsCollector.latestAnalysis,
                        processes: container.metricsCollector.latestProcesses
                    )
                }
            }
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
        case .logAnalyzer:
            LogAnalyzerView(events: container.eventLogService.events)
        case .menuBarStudio:
            MenuBarStudioView(store: container.v3.menuBarStudio)
        case .webDashboard:
            WebDashboardView(server: container.v3.webDashboard)
        case .reports:
            ReportsView(container: container)
        case .settings:
            SettingsView(viewModel: container.settingsViewModel)
        }
    }
}

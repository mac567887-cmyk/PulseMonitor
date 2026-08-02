import Foundation
import Observation

/// Composition root providing dependency-injected services and view models.
@MainActor
@Observable
public final class AppContainer {
    public let settings: AppSettings
    public let cpuService: CPUService
    public let gpuService: GPUService
    public let memoryService: MemoryService
    public let thermalService: ThermalService
    public let storageService: StorageService
    public let networkService: NetworkService
    public let batteryService: BatteryService
    public let processService: ProcessService
    public let historyRepository: HistoryRepository
    public let analysisEngine: BottleneckEngine
    public let gameDetector: GameDetector
    public let metricsCollector: MetricsCollector
    public let alertService: AlertService
    public let reportExporter: ReportExporter

    // Version 2 services
    public let capabilityService: CapabilityService
    public let smcService: SMCService
    public let systemControlService: SystemControlService
    public let appManagerService: AppManagerService
    public let benchmarkService: BenchmarkService
    public let eventLogService: EventLogService
    public let powerProfileService: PowerProfileService
    public let automationEngine: AutomationEngine
    public let insightEngine: InsightEngine
    public let autoOptimizer: AutoOptimizer
    public let pluginHost: PluginHost
    public let widgetBoardStore: WidgetBoardStore
    public let liveWallpaperService: LiveWallpaperService

    public let dashboardViewModel: DashboardViewModel
    public let cpuViewModel: CPUViewModel
    public let gpuViewModel: GPUViewModel
    public let memoryViewModel: MemoryViewModel
    public let thermalViewModel: ThermalViewModel
    public let storageViewModel: StorageViewModel
    public let networkViewModel: NetworkViewModel
    public let batteryViewModel: BatteryViewModel
    public let processViewModel: ProcessViewModel
    public let historyViewModel: HistoryViewModel
    public let gamesViewModel: GamesViewModel
    public let settingsViewModel: SettingsViewModel
    public let analysisViewModel: AnalysisViewModel

    public let controlCenterViewModel: ControlCenterViewModel
    public let benchmarkViewModel: BenchmarkViewModel
    public let optimizerViewModel: OptimizerViewModel
    public let appManagerViewModel: AppManagerViewModel
    public let insightsViewModel: InsightsViewModel
    public let overlayViewModel: OverlayViewModel

    public init() {
        let settings = AppSettings()
        self.settings = settings

        let cpu = CPUService()
        let gpu = GPUService()
        let memory = MemoryService()
        let thermal = ThermalService()
        let storage = StorageService()
        let network = NetworkService()
        let battery = BatteryService()
        let process = ProcessService()
        let history = HistoryRepository(settings: settings)
        let analysis = BottleneckEngine()
        let games = GameDetector()
        let alerts = AlertService(settings: settings)
        let reports = ReportExporter()

        self.cpuService = cpu
        self.gpuService = gpu
        self.memoryService = memory
        self.thermalService = thermal
        self.storageService = storage
        self.networkService = network
        self.batteryService = battery
        self.processService = process
        self.historyRepository = history
        self.analysisEngine = analysis
        self.gameDetector = games
        self.alertService = alerts
        self.reportExporter = reports

        let collector = MetricsCollector(
            settings: settings,
            cpuService: cpu,
            gpuService: gpu,
            memoryService: memory,
            thermalService: thermal,
            storageService: storage,
            networkService: network,
            batteryService: battery,
            processService: process,
            historyRepository: history,
            analysisEngine: analysis,
            gameDetector: games,
            alertService: alerts
        )
        self.metricsCollector = collector

        self.dashboardViewModel = DashboardViewModel(collector: collector, settings: settings)
        self.cpuViewModel = CPUViewModel(collector: collector)
        self.gpuViewModel = GPUViewModel(collector: collector)
        self.memoryViewModel = MemoryViewModel(collector: collector)
        self.thermalViewModel = ThermalViewModel(collector: collector)
        self.storageViewModel = StorageViewModel(collector: collector)
        self.networkViewModel = NetworkViewModel(collector: collector)
        self.batteryViewModel = BatteryViewModel(collector: collector)
        self.processViewModel = ProcessViewModel(collector: collector, processService: process)
        self.historyViewModel = HistoryViewModel(historyRepository: history, settings: settings)
        self.gamesViewModel = GamesViewModel(collector: collector, gameDetector: games)
        self.analysisViewModel = AnalysisViewModel(collector: collector)

        // Version 2 wiring.
        let capabilities = CapabilityService()
        let smc = SMCService()
        let control = SystemControlService(capabilityService: capabilities)
        let appManager = AppManagerService()
        let benchmarks = BenchmarkService()
        let eventLog = EventLogService()
        let profiles = PowerProfileService(settings: settings)
        let automation = AutomationEngine(
            settings: settings, eventLog: eventLog, profiles: profiles, alerts: alerts
        )
        let wallpaper = LiveWallpaperService()

        self.capabilityService = capabilities
        self.smcService = smc
        self.systemControlService = control
        self.appManagerService = appManager
        self.benchmarkService = benchmarks
        self.eventLogService = eventLog
        self.powerProfileService = profiles
        self.automationEngine = automation
        self.insightEngine = InsightEngine()
        self.autoOptimizer = AutoOptimizer()
        let plugins = PluginHost()
        plugins.bind(collector: collector)
        self.pluginHost = plugins
        self.widgetBoardStore = WidgetBoardStore()
        self.liveWallpaperService = wallpaper
        self.settingsViewModel = SettingsViewModel(settings: settings, liveWallpaper: wallpaper)

        self.controlCenterViewModel = ControlCenterViewModel(
            controlService: control, capabilityService: capabilities, smcService: smc
        )
        self.benchmarkViewModel = BenchmarkViewModel(service: benchmarks)
        self.optimizerViewModel = OptimizerViewModel(
            collector: collector, controlService: control, optimizer: AutoOptimizer()
        )
        self.appManagerViewModel = AppManagerViewModel(service: appManager)
        self.insightsViewModel = InsightsViewModel(
            collector: collector, history: history, eventLog: eventLog, engine: InsightEngine()
        )
        self.overlayViewModel = OverlayViewModel(collector: collector, settings: settings)

        collector.automationEngine = automation
        collector.eventLog = eventLog
        SharedAppContext.bind(self)
        plugins.scan()
    }

    public func start() {
        metricsCollector.start()
    }

    public func stop() {
        metricsCollector.stop()
    }
}

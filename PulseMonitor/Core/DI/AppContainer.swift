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
        self.settingsViewModel = SettingsViewModel(settings: settings)
        self.analysisViewModel = AnalysisViewModel(collector: collector)
    }

    public func start() {
        metricsCollector.start()
    }

    public func stop() {
        metricsCollector.stop()
    }
}

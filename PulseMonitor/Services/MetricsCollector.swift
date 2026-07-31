import Foundation
import Observation

/// Orchestrates low-overhead async polling across all metric services.
@MainActor
@Observable
public final class MetricsCollector {
    public private(set) var latestMetrics: SystemMetrics?
    public private(set) var latestProcesses: [ProcessInfoModel] = []
    public private(set) var latestAnalysis: AnalysisReport?
    public private(set) var detectedGames: [ProcessInfoModel] = []
    public private(set) var isRunning = false
    public private(set) var cpuHistory: [Double] = []
    public private(set) var memoryHistory: [Double] = []
    public private(set) var gpuHistory: [Double] = []
    public private(set) var networkInHistory: [Double] = []
    public private(set) var networkOutHistory: [Double] = []
    public private(set) var temperatureHistory: [Double] = []

    private let settings: AppSettings
    private let cpuService: CPUService
    private let gpuService: GPUService
    private let memoryService: MemoryService
    private let thermalService: ThermalService
    private let storageService: StorageService
    private let networkService: NetworkService
    private let batteryService: BatteryService
    private let processService: ProcessService
    private let historyRepository: HistoryRepository
    private let analysisEngine: BottleneckEngine
    private let gameDetector: GameDetector
    private let alertService: AlertService

    private var loopTask: Task<Void, Never>?
    private var previousMetrics: SystemMetrics?
    private let historyLimit = 120

    public init(
        settings: AppSettings,
        cpuService: CPUService,
        gpuService: GPUService,
        memoryService: MemoryService,
        thermalService: ThermalService,
        storageService: StorageService,
        networkService: NetworkService,
        batteryService: BatteryService,
        processService: ProcessService,
        historyRepository: HistoryRepository,
        analysisEngine: BottleneckEngine,
        gameDetector: GameDetector,
        alertService: AlertService
    ) {
        self.settings = settings
        self.cpuService = cpuService
        self.gpuService = gpuService
        self.memoryService = memoryService
        self.thermalService = thermalService
        self.storageService = storageService
        self.networkService = networkService
        self.batteryService = batteryService
        self.processService = processService
        self.historyRepository = historyRepository
        self.analysisEngine = analysisEngine
        self.gameDetector = gameDetector
        self.alertService = alertService
    }

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        loopTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                await self.tick()
                let interval = UInt64(max(0.5, self.settings.refreshIntervalSeconds) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: interval)
            }
        }
    }

    public func stop() {
        isRunning = false
        loopTask?.cancel()
        loopTask = nil
    }

    private func tick() async {
        async let cpu = cpuService.sample()
        async let gpu = gpuService.sample()
        async let memory = memoryService.sample()
        async let thermal = thermalService.sample()
        async let storage = storageService.sample()
        async let network = networkService.sample()
        async let battery = batteryService.sample()
        async let processes = processService.listProcesses()

        let (cpuM, gpuM, memM, thermM, storM, netM, battM, procs) = await (cpu, gpu, memory, thermal, storage, network, battery, processes)

        if let ws = procs.first(where: { $0.name == "WindowServer" }) {
            await gpuService.updateWindowServerCPU(ws.cpuPercent)
        }

        let uptime = ProcessInfo.processInfo.systemUptime
        let power = PowerMetrics(
            packageWatts: cpuM.packagePowerWatts ?? 0,
            gpuWatts: gpuM.powerWatts ?? 0,
            totalSystemWatts: battM.wattage ?? ((cpuM.packagePowerWatts ?? 0) + (gpuM.powerWatts ?? 0)),
            isEstimated: battM.wattage == nil
        )

        let metrics = SystemMetrics(
            cpu: cpuM,
            gpu: gpuM,
            memory: memM,
            thermal: thermM,
            storage: storM,
            network: netM,
            battery: battM,
            power: power,
            uptime: uptime
        )

        let analysis = await analysisEngine.analyze(metrics: metrics, processes: procs, previous: previousMetrics)
        let games = await gameDetector.detect(in: procs)

        latestMetrics = metrics
        latestProcesses = procs
        latestAnalysis = analysis
        detectedGames = games

        appendHistory(cpuM.totalUsage, to: &cpuHistory)
        appendHistory(memM.usagePercent, to: &memoryHistory)
        appendHistory(gpuM.utilization, to: &gpuHistory)
        appendHistory(netM.bytesInPerSec, to: &networkInHistory)
        appendHistory(netM.bytesOutPerSec, to: &networkOutHistory)
        if let temp = thermM.cpuTemperatureC ?? thermM.batteryTemperatureC {
            appendHistory(temp, to: &temperatureHistory)
        }

        await historyRepository.insert(metrics: metrics)
        await alertService.evaluate(metrics: metrics, analysis: analysis)

        previousMetrics = metrics
    }

    private func appendHistory(_ value: Double, to array: inout [Double]) {
        array.append(value)
        if array.count > historyLimit {
            array.removeFirst(array.count - historyLimit)
        }
    }
}

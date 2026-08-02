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

    /// Full snapshots kept in memory so the insight engine can correlate fields
    /// the summary database does not store. Capped at roughly thirty minutes of
    /// one-second sampling, which costs a couple of megabytes.
    public private(set) var recentSamples: [SystemMetrics] = []
    private let recentSampleLimit = 1_800

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

    /// Set after construction because these depend on the collector existing.
    public weak var automationEngine: AutomationEngine?
    public weak var eventLog: EventLogService?

    private var loopTask: Task<Void, Never>?
    private var activityToken: NSObjectProtocol?
    private var previousMetrics: SystemMetrics?
    private var lastProcessScan: Date?

    /// How often the full process table is rebuilt. Never faster than the
    /// sampling interval, and never slower than needed to keep the Processes
    /// view feeling live.
    private var processScanInterval: TimeInterval {
        max(settings.refreshIntervalSeconds, 3.0)
    }
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

        // Without this, App Nap suspends the sampling loop whenever the window is
        // occluded, leaving gaps in history exactly when the user is busy in
        // another app. Sleep and display sleep are deliberately not blocked.
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated],
            reason: "Continuous system metrics sampling"
        )

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
        if let activityToken {
            ProcessInfo.processInfo.endActivity(activityToken)
            self.activityToken = nil
        }
    }

    private func tick() async {
        async let cpu = cpuService.sample()
        async let gpu = gpuService.sample()
        async let memory = memoryService.sample()
        async let thermal = thermalService.sample()
        async let storage = storageService.sample()
        async let network = networkService.sample()
        async let battery = batteryService.sample()

        let (cpuM, gpuM, memM, thermM, storM, netM, battM) = await (cpu, gpu, memory, thermal, storage, network, battery)

        // Enumerating every process means a proc_pidinfo call per PID, which
        // dominates the cost of a tick. Process rows do not need to refresh at
        // the full sampling rate, so they run on their own slower cadence and
        // the previous list is reused in between.
        let procs: [ProcessInfoModel]
        let now = Date()
        if lastProcessScan.map({ now.timeIntervalSince($0) >= processScanInterval }) ?? true {
            procs = await processService.listProcesses()
            lastProcessScan = now
            latestProcesses = procs
        } else {
            procs = latestProcesses
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
        latestAnalysis = analysis
        detectedGames = games

        appendHistory(cpuM.totalUsage, to: &cpuHistory)
        appendHistory(memM.usagePercent, to: &memoryHistory)
        if let gpuLoad = gpuM.utilization {
            appendHistory(gpuLoad, to: &gpuHistory)
        }
        appendHistory(netM.bytesInPerSec, to: &networkInHistory)
        appendHistory(netM.bytesOutPerSec, to: &networkOutHistory)
        if let temp = thermM.cpuTemperatureC ?? thermM.batteryTemperatureC {
            appendHistory(temp, to: &temperatureHistory)
        }

        recentSamples.append(metrics)
        if recentSamples.count > recentSampleLimit {
            recentSamples.removeFirst(recentSamples.count - recentSampleLimit)
        }

        if battM.isPresent, let percent = battM.chargePercent {
            eventLog?.noteBattery(percent: Int(percent), isCharging: battM.isCharging)
        }
        automationEngine?.evaluate(metrics: metrics, processes: procs)

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

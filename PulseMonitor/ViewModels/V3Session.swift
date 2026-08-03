import Foundation
import Observation

/// Owns Version 3.0 live state derived from the shared collector.
@MainActor
@Observable
public final class V3Session {
    public private(set) var health: HealthScoreReport?
    public private(set) var healthHistory: [HealthScoreReport] = []
    public private(set) var twin: DigitalTwinState?
    public private(set) var copilotMessages: [CopilotMessage] = []
    public private(set) var hardware: HardwareInventory?
    public var searchQuery = ""
    public private(set) var searchHits: [SearchHit] = []

    public let snapshots = SnapshotService()
    public let gameLab = GameLabService()
    public let usb = USBDeviceService()
    public let bluetooth = BluetoothLabService()
    public let displays = DisplayLabService()
    public let packages = PackageManagerService()
    public let workspaces = WorkspaceStore()
    public let menuBarStudio = MenuBarStudioStore()
    public let webDashboard = WebDashboardServer()
    public let hardwareDB = HardwareDatabaseService()

    private let healthEngine = HealthScoreEngine()
    private let twinEngine = DigitalTwinEngine()
    private let copilot = CopilotEngine()
    private let search = UniversalSearchService()
    private var previousMetrics: SystemMetrics?

    public init() {}

    public func bind(collector: MetricsCollector) {
        webDashboard.bind(collector: collector)
    }

    public func tick(
        metrics: SystemMetrics,
        processes: [ProcessInfoModel],
        findings: [BottleneckFinding],
        games: [ProcessInfoModel],
        events: [SystemEvent]
    ) {
        let report = healthEngine.evaluate(
            metrics: metrics,
            processes: processes,
            findings: findings,
            previous: health
        )
        health = report
        healthHistory.append(report)
        if healthHistory.count > 240 { healthHistory.removeFirst(healthHistory.count - 240) }

        twin = twinEngine.project(
            metrics: metrics,
            previous: previousMetrics,
            usbCount: usb.devices.count
        )
        copilotMessages = copilot.brief(
            metrics: metrics,
            processes: processes,
            findings: findings,
            games: games
        )
        gameLab.ingest(metrics: metrics, processes: processes, detectedGames: games)
        previousMetrics = metrics

        if !searchQuery.isEmpty {
            searchHits = search.search(
                query: searchQuery,
                processes: processes,
                hardware: hardware,
                events: events,
                twin: twin
            )
        }
    }

    public func refreshHardware() async {
        hardware = await hardwareDB.inventory()
    }

    public func updateSearch(processes: [ProcessInfoModel], events: [SystemEvent]) {
        searchHits = search.search(
            query: searchQuery,
            processes: processes,
            hardware: hardware,
            events: events,
            twin: twin
        )
    }

    public func captureSnapshot(metrics: SystemMetrics, analysis: AnalysisReport?, processes: [ProcessInfoModel]) {
        snapshots.capture(metrics: metrics, analysis: analysis, processes: processes)
    }
}

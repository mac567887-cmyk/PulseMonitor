import Foundation
import Observation
import SwiftUI

/// Drives the benchmark suite screen.
@MainActor
@Observable
public final class BenchmarkViewModel {
    public private(set) var results: [BenchmarkResult] = []
    public private(set) var running: BenchmarkKind?
    public private(set) var latest: [BenchmarkKind: BenchmarkResult] = [:]
    public private(set) var deltas: [BenchmarkKind: Double] = [:]

    private let service: BenchmarkService

    public init(service: BenchmarkService) {
        self.service = service
    }

    public func load() async {
        results = await service.storedResults()
        rebuildLatest()
    }

    public func run(_ kind: BenchmarkKind) async {
        guard running == nil else { return }
        running = kind
        defer { running = nil }

        let previous = await service.previousScore(for: kind, excluding: UUID())
        let result = await service.run(kind)

        if let previous, previous > 0 {
            deltas[kind] = (result.score - previous) / previous * 100
        } else {
            deltas[kind] = nil
        }

        results = await service.storedResults()
        rebuildLatest()
    }

    /// Runs every benchmark in sequence. Disk read follows disk write so there
    /// is a file to read back.
    public func runAll() async {
        let order: [BenchmarkKind] = [
            .cpuSingleCore, .cpuMultiCore, .memoryBandwidth, .diskWrite, .diskRead, .gpuCompute
        ]
        for kind in order {
            await run(kind)
        }
        await service.removeScratchFile()
    }

    public func history(for kind: BenchmarkKind) async -> [BenchmarkResult] {
        await service.results(for: kind)
    }

    public func clear() async {
        await service.clearHistory()
        results = []
        latest = [:]
        deltas = [:]
    }

    private func rebuildLatest() {
        var newest: [BenchmarkKind: BenchmarkResult] = [:]
        for result in results {
            if let existing = newest[result.kind], existing.date > result.date { continue }
            newest[result.kind] = result
        }
        latest = newest
    }
}

/// Drives the Auto Optimizer screen.
@MainActor
@Observable
public final class OptimizerViewModel {
    public private(set) var suggestions: [OptimizationSuggestion] = []
    public private(set) var isAnalyzing = false
    public private(set) var lastRun: Date?
    public private(set) var actionError: String?
    /// Suggestions the user has already acted on, kept so the list does not
    /// silently re-order underneath them.
    public private(set) var completed: Set<UUID> = []

    private let collector: MetricsCollector
    private let controlService: SystemControlService
    private let optimizer: AutoOptimizer

    public init(
        collector: MetricsCollector,
        controlService: SystemControlService,
        optimizer: AutoOptimizer
    ) {
        self.collector = collector
        self.controlService = controlService
        self.optimizer = optimizer
    }

    public func analyze() async {
        guard let metrics = collector.latestMetrics else { return }
        isAnalyzing = true
        defer { isAnalyzing = false }

        let agents = await controlService.userLaunchAgents()
        // Give the spinner a beat so a sub-100ms analysis does not flash.
        try? await Task.sleep(nanoseconds: 350_000_000)

        suggestions = optimizer.suggestions(
            metrics: metrics,
            processes: collector.latestProcesses,
            launchAgentCount: agents.count
        )
        completed = []
        lastRun = Date()
    }

    public func perform(_ suggestion: OptimizationSuggestion) {
        if let error = AutoOptimizer.perform(suggestion) {
            actionError = error
        } else {
            actionError = nil
            completed.insert(suggestion.id)
        }
    }

    public func dismissError() {
        actionError = nil
    }
}

/// Drives the Application Manager screen.
@MainActor
@Observable
public final class AppManagerViewModel {
    public private(set) var apps: [InstalledApp] = []
    public private(set) var isLoading = false
    public var searchText = ""
    public var architectureFilter: BinaryArchitecture?
    public private(set) var actionError: String?

    private let service: AppManagerService

    public init(service: AppManagerService) {
        self.service = service
    }

    public var filtered: [InstalledApp] {
        var result = apps
        if let architectureFilter {
            result = result.filter { $0.architecture == architectureFilter }
        }
        let query = searchText.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(query)
                    || ($0.developer?.localizedCaseInsensitiveContains(query) ?? false)
                    || ($0.bundleIdentifier?.localizedCaseInsensitiveContains(query) ?? false)
            }
        }
        return result
    }

    public var architectureCounts: [BinaryArchitecture: Int] {
        Dictionary(grouping: apps, by: \.architecture).mapValues(\.count)
    }

    public func load(forceRefresh: Bool = false) async {
        isLoading = true
        defer { isLoading = false }
        apps = await service.installedApps(forceRefresh: forceRefresh)
    }

    public func permissions(for app: InstalledApp) -> [(key: String, description: String)] {
        service.declaredPermissions(for: app)
    }

    public func crashReports(for app: InstalledApp) -> [AppManagerService.CrashReport] {
        service.crashReports(for: app)
    }

    public func containerURL(for app: InstalledApp) -> URL? {
        service.containerURL(for: app)
    }

    public func preferencesURL(for app: InstalledApp) -> URL? {
        service.preferencesURL(for: app)
    }

    public func moveToTrash(_ app: InstalledApp) async {
        if let message = await AppManagerService.moveToTrash(app) {
            actionError = message
        } else {
            actionError = nil
            await load(forceRefresh: true)
        }
    }

    public func dismissError() {
        actionError = nil
    }
}

/// Drives the Smart Insights screen.
@MainActor
@Observable
public final class InsightsViewModel {
    public private(set) var insights: [Insight] = []
    public private(set) var isLoading = false
    public private(set) var sampleCount = 0
    /// Actual time span the samples cover, which may be shorter than the
    /// requested window if the app has not been running long enough.
    public private(set) var coveredInterval: TimeInterval = 0

    public var window: WindowLength = .thirtyMinutes

    /// Insight windows are bounded by the in-memory sample buffer, so the
    /// choices offered here are the ones the app can genuinely honour.
    public enum WindowLength: String, CaseIterable, Identifiable, Sendable {
        case fiveMinutes, fifteenMinutes, thirtyMinutes

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .fiveMinutes: "5 min"
            case .fifteenMinutes: "15 min"
            case .thirtyMinutes: "30 min"
            }
        }

        public var seconds: TimeInterval {
            switch self {
            case .fiveMinutes: 300
            case .fifteenMinutes: 900
            case .thirtyMinutes: 1_800
            }
        }
    }

    private let collector: MetricsCollector
    private let history: HistoryRepository
    private let eventLog: EventLogService
    private let engine: InsightEngine

    public init(
        collector: MetricsCollector,
        history: HistoryRepository,
        eventLog: EventLogService,
        engine: InsightEngine
    ) {
        self.collector = collector
        self.history = history
        self.eventLog = eventLog
        self.engine = engine
    }

    public func refresh() async {
        isLoading = true
        defer { isLoading = false }

        let cutoff = Date().addingTimeInterval(-window.seconds)
        let samples = collector.recentSamples.filter { $0.timestamp >= cutoff }
        sampleCount = samples.count
        coveredInterval = if let first = samples.first, let last = samples.last {
            last.timestamp.timeIntervalSince(first.timestamp)
        } else {
            0
        }

        // The busiest processes give insights something concrete to name.
        let topProcesses = collector.latestProcesses
            .sorted { $0.cpuPercent > $1.cpuPercent }
            .prefix(3)
            .map(\.name)

        insights = engine.insights(
            from: samples,
            events: eventLog.events,
            topProcessNames: Array(topProcesses)
        )
    }
}

/// Feeds the floating performance overlay.
///
/// Reads straight from the shared collector so the overlay costs nothing beyond
/// rendering; it never starts polling of its own.
@MainActor
@Observable
public final class OverlayViewModel {
    private let collector: MetricsCollector
    private let settings: AppSettings

    public init(collector: MetricsCollector, settings: AppSettings) {
        self.collector = collector
        self.settings = settings
    }

    public var metrics: SystemMetrics? { collector.latestMetrics }
    public var cpuHistory: [Double] { collector.cpuHistory }

    public var enabledMetrics: [AppSettings.OverlayMetric] {
        AppSettings.OverlayMetric.allCases.filter { settings.overlayMetrics.contains($0) }
    }

    public func value(for metric: AppSettings.OverlayMetric) -> String {
        guard let metrics else { return "—" }
        switch metric {
        case .cpu:
            return String(format: "%.0f%%", metrics.cpu.totalUsage)
        case .gpu:
            guard let gpu = metrics.gpu.utilization else { return "n/a" }
            return String(format: "%.0f%%", gpu)
        case .memory:
            return String(format: "%.0f%%", metrics.memory.usagePercent)
        case .temperature:
            guard let temperature = metrics.thermal.cpuTemperatureC ?? metrics.thermal.batteryTemperatureC else {
                return "n/a"
            }
            return String(format: "%.0f°", temperature)
        case .battery:
            guard metrics.battery.isPresent, let percent = metrics.battery.chargePercent else { return "n/a" }
            return String(format: "%.0f%%", percent)
        case .network:
            return "\(Formatters.bytes(UInt64(metrics.network.bytesInPerSec)))/s"
        case .disk:
            let total = metrics.storage.readBytesPerSec + metrics.storage.writeBytesPerSec
            return "\(Formatters.bytes(UInt64(total)))/s"
        }
    }

    /// Fraction used to colour the readout; nil when the metric has no natural scale.
    public func fraction(for metric: AppSettings.OverlayMetric) -> Double? {
        guard let metrics else { return nil }
        switch metric {
        case .cpu: return metrics.cpu.totalUsage / 100
        case .gpu: return metrics.gpu.utilization.map { $0 / 100 }
        case .memory: return metrics.memory.usagePercent / 100
        case .temperature:
            guard let temperature = metrics.thermal.cpuTemperatureC else { return nil }
            // 40°C reads as cool, 100°C as maxed out.
            return min(1, max(0, (temperature - 40) / 60))
        case .battery:
            guard let percent = metrics.battery.chargePercent else { return nil }
            return percent / 100
        case .network, .disk:
            return nil
        }
    }
}

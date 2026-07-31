import Foundation
import Observation

@MainActor
@Observable
public final class DashboardViewModel {
    public let collector: MetricsCollector
    public let settings: AppSettings

    public init(collector: MetricsCollector, settings: AppSettings) {
        self.collector = collector
        self.settings = settings
    }

    public var metrics: SystemMetrics? { collector.latestMetrics }
    public var analysis: AnalysisReport? { collector.latestAnalysis }
    public var healthScore: Double { analysis?.overallHealthScore ?? 100 }
    public var narrative: String { analysis?.narrative ?? "Collecting metrics…" }

    public func status(for value: Double, warning: Double = 70, critical: Double = 90) -> MetricStatus {
        if value >= critical { return .critical }
        if value >= warning { return .warning }
        return .ok
    }
}

public enum MetricStatus: String, Sendable {
    case ok, warning, critical

    public var label: String {
        switch self {
        case .ok: "OK"
        case .warning: "Watch"
        case .critical: "Critical"
        }
    }
}

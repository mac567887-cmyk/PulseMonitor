import Foundation

/// Protocol for bottleneck detection and explanation engines.
public protocol AnalysisEngine: Actor {
    func analyze(metrics: SystemMetrics, processes: [ProcessInfoModel], previous: SystemMetrics?) async -> AnalysisReport
}

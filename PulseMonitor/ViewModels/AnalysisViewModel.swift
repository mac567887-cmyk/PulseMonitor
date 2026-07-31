import Foundation
import Observation

@MainActor
@Observable
public final class AnalysisViewModel {
    public let collector: MetricsCollector
    public init(collector: MetricsCollector) { self.collector = collector }
    public var report: AnalysisReport? { collector.latestAnalysis }
}

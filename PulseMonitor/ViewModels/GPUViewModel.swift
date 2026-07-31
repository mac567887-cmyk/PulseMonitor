import Foundation
import Observation

@MainActor
@Observable
public final class GPUViewModel {
    public let collector: MetricsCollector
    public init(collector: MetricsCollector) { self.collector = collector }
    public var metrics: GPUMetrics? { collector.latestMetrics?.gpu }
    public var history: [Double] { collector.gpuHistory }
    public var trend: TrendCalculator.Trend { TrendCalculator.trend(of: history) }
}

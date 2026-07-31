import Foundation
import Observation

@MainActor
@Observable
public final class CPUViewModel {
    public let collector: MetricsCollector
    public init(collector: MetricsCollector) { self.collector = collector }
    public var metrics: CPUMetrics? { collector.latestMetrics?.cpu }
    public var history: [Double] { collector.cpuHistory }
    public var topProcesses: [ProcessInfoModel] {
        Array(collector.latestProcesses.sorted { $0.cpuPercent > $1.cpuPercent }.prefix(15))
    }
    public var trend: TrendCalculator.Trend { TrendCalculator.trend(of: history) }
    public var prediction: Double? { TrendCalculator.predictNext(of: history) }
}

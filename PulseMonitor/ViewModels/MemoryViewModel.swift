import Foundation
import Observation

@MainActor
@Observable
public final class MemoryViewModel {
    public let collector: MetricsCollector
    public init(collector: MetricsCollector) { self.collector = collector }
    public var metrics: MemoryMetrics? { collector.latestMetrics?.memory }
    public var history: [Double] { collector.memoryHistory }
    public var topConsumers: [ProcessInfoModel] {
        Array(collector.latestProcesses.sorted { $0.memoryBytes > $1.memoryBytes }.prefix(15))
    }
    public var trend: TrendCalculator.Trend { TrendCalculator.trend(of: history) }
}

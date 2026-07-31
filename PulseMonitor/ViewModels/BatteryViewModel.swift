import Foundation
import Observation

@MainActor
@Observable
public final class BatteryViewModel {
    public let collector: MetricsCollector
    public init(collector: MetricsCollector) { self.collector = collector }
    public var metrics: BatteryMetrics? { collector.latestMetrics?.battery }
}

import Foundation
import Observation

@MainActor
@Observable
public final class ThermalViewModel {
    public let collector: MetricsCollector
    public init(collector: MetricsCollector) { self.collector = collector }
    public var metrics: ThermalMetrics? { collector.latestMetrics?.thermal }
    public var history: [Double] { collector.temperatureHistory }
}

import Foundation
import Observation

@MainActor
@Observable
public final class NetworkViewModel {
    public let collector: MetricsCollector
    public init(collector: MetricsCollector) { self.collector = collector }
    public var metrics: NetworkMetrics? { collector.latestMetrics?.network }
    public var inHistory: [Double] { collector.networkInHistory }
    public var outHistory: [Double] { collector.networkOutHistory }
}

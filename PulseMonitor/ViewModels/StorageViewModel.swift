import Foundation
import Observation

@MainActor
@Observable
public final class StorageViewModel {
    public let collector: MetricsCollector
    public init(collector: MetricsCollector) { self.collector = collector }
    public var metrics: StorageMetrics? { collector.latestMetrics?.storage }
}

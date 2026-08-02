import Foundation

/// GPU utilization, memory, and Metal activity metrics.
///
/// The utilization figures are optional on purpose. Not every GPU driver
/// publishes performance statistics, and a missing counter must stay missing so
/// the UI can say so rather than draw a zero.
public struct GPUMetrics: Sendable, Codable, Equatable {
    public let utilization: Double?
    public let rendererUtilization: Double?
    public let tilerUtilization: Double?
    public let deviceUtilization: Double?
    public let frequencyMHz: Double?
    public let memoryUsedBytes: UInt64?
    public let memoryTotalBytes: UInt64?
    public let powerWatts: Double?
    public let temperatureC: Double?
    public let deviceName: String
    public let isMetalActive: Bool

    /// Whether the driver exposed any utilization counter at all.
    public var hasUtilizationCounters: Bool { utilization != nil }

    public static let empty = GPUMetrics(
        utilization: nil, rendererUtilization: nil, tilerUtilization: nil,
        deviceUtilization: nil, frequencyMHz: nil, memoryUsedBytes: nil,
        memoryTotalBytes: nil, powerWatts: nil, temperatureC: nil,
        deviceName: "Unknown GPU", isMetalActive: false
    )
}

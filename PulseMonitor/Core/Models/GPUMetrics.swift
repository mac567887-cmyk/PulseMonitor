import Foundation

/// GPU utilization, memory, and Metal activity metrics.
public struct GPUMetrics: Sendable, Codable, Equatable {
    public let utilization: Double
    public let rendererUtilization: Double
    public let tilerUtilization: Double
    public let frequencyMHz: Double?
    public let memoryUsedBytes: UInt64?
    public let memoryTotalBytes: UInt64?
    public let powerWatts: Double?
    public let deviceName: String
    public let isMetalActive: Bool
    public let windowServerCPU: Double?

    public static let empty = GPUMetrics(
        utilization: 0, rendererUtilization: 0, tilerUtilization: 0,
        frequencyMHz: nil, memoryUsedBytes: nil, memoryTotalBytes: nil,
        powerWatts: nil, deviceName: "Unknown GPU", isMetalActive: false, windowServerCPU: nil
    )
}

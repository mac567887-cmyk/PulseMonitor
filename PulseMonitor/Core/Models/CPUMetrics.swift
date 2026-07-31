import Foundation

/// Detailed CPU utilization, frequency, and scheduling statistics.
public struct CPUMetrics: Sendable, Codable, Equatable {
    public let totalUsage: Double
    public let userUsage: Double
    public let systemUsage: Double
    public let idleUsage: Double
    public let niceUsage: Double
    public let perCoreUsage: [Double]
    public let performanceCoreUsage: [Double]
    public let efficiencyCoreUsage: [Double]
    public let performanceCoreCount: Int
    public let efficiencyCoreCount: Int
    public let logicalCoreCount: Int
    public let physicalCoreCount: Int
    public let currentFrequencyMHz: Double?
    public let maxFrequencyMHz: Double?
    public let loadAverage1: Double
    public let loadAverage5: Double
    public let loadAverage15: Double
    public let processCount: Int
    public let threadCount: Int
    public let contextSwitches: UInt64
    public let interrupts: UInt64
    public let packagePowerWatts: Double?
    public let brand: String
    public let architecture: CPUArchitecture
    public let isThrottling: Bool

    public enum CPUArchitecture: String, Sendable, Codable, Equatable {
        case appleSilicon
        case intel
        case unknown
    }

    public static let empty = CPUMetrics(
        totalUsage: 0, userUsage: 0, systemUsage: 0, idleUsage: 100, niceUsage: 0,
        perCoreUsage: [], performanceCoreUsage: [], efficiencyCoreUsage: [],
        performanceCoreCount: 0, efficiencyCoreCount: 0,
        logicalCoreCount: 0, physicalCoreCount: 0,
        currentFrequencyMHz: nil, maxFrequencyMHz: nil,
        loadAverage1: 0, loadAverage5: 0, loadAverage15: 0,
        processCount: 0, threadCount: 0, contextSwitches: 0, interrupts: 0,
        packagePowerWatts: nil, brand: "Unknown", architecture: .unknown, isThrottling: false
    )
}

/// A single process CPU sample for ranking and heat maps.
public struct ProcessCPUSample: Sendable, Codable, Identifiable, Equatable {
    public let id: Int32
    public let name: String
    public let cpuPercent: Double
    public let memoryBytes: UInt64
    public let threadCount: Int
    public let architecture: String
    public let path: String?
}

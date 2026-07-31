import Foundation

/// Physical memory, swap, compression, and pressure statistics.
public struct MemoryMetrics: Sendable, Codable, Equatable {
    public let totalBytes: UInt64
    public let usedBytes: UInt64
    public let freeBytes: UInt64
    public let activeBytes: UInt64
    public let inactiveBytes: UInt64
    public let wiredBytes: UInt64
    public let compressedBytes: UInt64
    public let appMemoryBytes: UInt64
    public let cachedBytes: UInt64
    public let swapUsedBytes: UInt64
    public let swapTotalBytes: UInt64
    public let pressure: MemoryPressure
    public let pageIns: UInt64
    public let pageOuts: UInt64
    public let compressions: UInt64
    public let decompressions: UInt64

    public enum MemoryPressure: String, Sendable, Codable, Equatable {
        case normal
        case warning
        case critical

        public var displayName: String {
            switch self {
            case .normal: "Normal"
            case .warning: "Warning"
            case .critical: "Critical"
            }
        }
    }

    public var usagePercent: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalBytes) * 100.0
    }

    public static let empty = MemoryMetrics(
        totalBytes: 0, usedBytes: 0, freeBytes: 0, activeBytes: 0, inactiveBytes: 0,
        wiredBytes: 0, compressedBytes: 0, appMemoryBytes: 0, cachedBytes: 0,
        swapUsedBytes: 0, swapTotalBytes: 0, pressure: .normal,
        pageIns: 0, pageOuts: 0, compressions: 0, decompressions: 0
    )
}

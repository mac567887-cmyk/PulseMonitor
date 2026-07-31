import Foundation

/// Disk capacity, I/O throughput, latency, and SMART health.
public struct StorageMetrics: Sendable, Codable, Equatable {
    public let volumes: [VolumeInfo]
    public let readBytesPerSec: Double
    public let writeBytesPerSec: Double
    public let readOpsPerSec: Double
    public let writeOpsPerSec: Double
    public let averageLatencyMs: Double?
    public let queueDepth: Double?
    public let smartHealth: SMARTHealth

    public struct VolumeInfo: Sendable, Codable, Equatable, Identifiable {
        public var id: String { path }
        public let name: String
        public let path: String
        public let totalBytes: UInt64
        public let freeBytes: UInt64
        public let isSSD: Bool
        public let isRoot: Bool

        public var usedBytes: UInt64 { totalBytes &- freeBytes }
        public var usedPercent: Double {
            guard totalBytes > 0 else { return 0 }
            return Double(usedBytes) / Double(totalBytes) * 100.0
        }
    }

    public enum SMARTHealth: String, Sendable, Codable, Equatable {
        case verified
        case unknown
        case failing
        case unsupported

        public var displayName: String {
            switch self {
            case .verified: "Verified"
            case .unknown: "Unknown"
            case .failing: "Failing"
            case .unsupported: "Unsupported"
            }
        }
    }

    public static let empty = StorageMetrics(
        volumes: [], readBytesPerSec: 0, writeBytesPerSec: 0,
        readOpsPerSec: 0, writeOpsPerSec: 0, averageLatencyMs: nil,
        queueDepth: nil, smartHealth: .unknown
    )
}

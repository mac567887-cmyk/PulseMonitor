import Foundation

/// Network throughput, latency, and connection activity.
public struct NetworkMetrics: Sendable, Codable, Equatable {
    public let bytesInPerSec: Double
    public let bytesOutPerSec: Double
    public let packetsInPerSec: Double
    public let packetsOutPerSec: Double
    public let totalBytesIn: UInt64
    public let totalBytesOut: UInt64
    public let activeConnections: Int
    public let latencyMs: Double?
    public let interfaces: [InterfaceInfo]

    public struct InterfaceInfo: Sendable, Codable, Equatable, Identifiable {
        public var id: String { name }
        public let name: String
        public let displayName: String
        public let bytesInPerSec: Double
        public let bytesOutPerSec: Double
        public let isActive: Bool
        public let kind: String
    }

    public static let empty = NetworkMetrics(
        bytesInPerSec: 0, bytesOutPerSec: 0, packetsInPerSec: 0, packetsOutPerSec: 0,
        totalBytesIn: 0, totalBytesOut: 0, activeConnections: 0, latencyMs: nil, interfaces: []
    )
}

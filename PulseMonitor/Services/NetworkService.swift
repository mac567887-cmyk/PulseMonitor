import Foundation
import Darwin

/// Monitors network interface counters via `getifaddrs` differential sampling.
public actor NetworkService: MetricProviding {
    public typealias Metric = NetworkMetrics

    private struct Counters {
        var bytesIn: UInt64
        var bytesOut: UInt64
        var packetsIn: UInt64
        var packetsOut: UInt64
    }

    private var previous: [String: Counters] = [:]
    private var previousTimestamp: Date?

    public init() {}

    public func sample() async -> NetworkMetrics {
        let current = Self.readInterfaceCounters()
        let now = Date()
        let dt = previousTimestamp.map { now.timeIntervalSince($0) } ?? 0

        var totalIn: UInt64 = 0
        var totalOut: UInt64 = 0
        var bytesInPerSec = 0.0
        var bytesOutPerSec = 0.0
        var packetsInPerSec = 0.0
        var packetsOutPerSec = 0.0
        var interfaces: [NetworkMetrics.InterfaceInfo] = []

        for (name, counters) in current {
            totalIn &+= counters.bytesIn
            totalOut &+= counters.bytesOut

            var inBps = 0.0, outBps = 0.0
            if dt > 0, let prev = previous[name] {
                inBps = Double(counters.bytesIn &- prev.bytesIn) / dt
                outBps = Double(counters.bytesOut &- prev.bytesOut) / dt
                packetsInPerSec += Double(counters.packetsIn &- prev.packetsIn) / dt
                packetsOutPerSec += Double(counters.packetsOut &- prev.packetsOut) / dt
                bytesInPerSec += inBps
                bytesOutPerSec += outBps
            }

            let kind: String
            if name.hasPrefix("en") { kind = "Ethernet/Wi-Fi" }
            else if name.hasPrefix("utun") || name.hasPrefix("ipsec") { kind = "VPN" }
            else if name.hasPrefix("awdl") || name.hasPrefix("llw") { kind = "AWDL" }
            else if name.hasPrefix("lo") { kind = "Loopback" }
            else { kind = "Other" }

            let isActive = inBps + outBps > 1
            if !name.hasPrefix("lo") {
                interfaces.append(
                    NetworkMetrics.InterfaceInfo(
                        name: name,
                        displayName: name,
                        bytesInPerSec: max(0, inBps),
                        bytesOutPerSec: max(0, outBps),
                        isActive: isActive,
                        kind: kind
                    )
                )
            }
        }

        previous = current
        previousTimestamp = now

        return NetworkMetrics(
            bytesInPerSec: max(0, bytesInPerSec),
            bytesOutPerSec: max(0, bytesOutPerSec),
            packetsInPerSec: max(0, packetsInPerSec),
            packetsOutPerSec: max(0, packetsOutPerSec),
            totalBytesIn: totalIn,
            totalBytesOut: totalOut,
            activeConnections: 0,
            latencyMs: nil,
            interfaces: interfaces.sorted { $0.bytesInPerSec + $0.bytesOutPerSec > $1.bytesInPerSec + $1.bytesOutPerSec }
        )
    }

    private static func readInterfaceCounters() -> [String: Counters] {
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let first = ifaddrPtr else { return [:] }
        defer { freeifaddrs(ifaddrPtr) }

        var result: [String: Counters] = [:]
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let current = ptr {
            let name = String(cString: current.pointee.ifa_name)
            if let data = current.pointee.ifa_data {
                let addr = current.pointee.ifa_addr.pointee
                if addr.sa_family == UInt8(AF_LINK) {
                    let networkData = data.assumingMemoryBound(to: if_data.self)
                    let counters = Counters(
                        bytesIn: UInt64(networkData.pointee.ifi_ibytes),
                        bytesOut: UInt64(networkData.pointee.ifi_obytes),
                        packetsIn: UInt64(networkData.pointee.ifi_ipackets),
                        packetsOut: UInt64(networkData.pointee.ifi_opackets)
                    )
                    result[name] = counters
                }
            }
            ptr = current.pointee.ifa_next
        }
        return result
    }
}

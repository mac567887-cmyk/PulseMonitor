import Foundation
import Darwin
import DiskArbitration
import IOKit

/// Monitors volume capacity and disk I/O counters via `statfs` and `host_statistics`.
public actor StorageService: MetricProviding {
    public typealias Metric = StorageMetrics

    private var previousReadBytes: UInt64 = 0
    private var previousWriteBytes: UInt64 = 0
    private var previousReadOps: UInt64 = 0
    private var previousWriteOps: UInt64 = 0
    private var previousTimestamp: Date?

    public init() {}

    public func sample() async -> StorageMetrics {
        let volumes = Self.enumerateVolumes()
        let io = sampleIO()

        return StorageMetrics(
            volumes: volumes,
            readBytesPerSec: io.readBps,
            writeBytesPerSec: io.writeBps,
            readOpsPerSec: io.readOps,
            writeOpsPerSec: io.writeOps,
            averageLatencyMs: nil,
            queueDepth: nil,
            smartHealth: .unknown
        )
    }

    private func sampleIO() -> (readBps: Double, writeBps: Double, readOps: Double, writeOps: Double) {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        _ = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        // Prefer getiopolicy / sysctl disk counters when available.
        // Use IOKit IOBlockStorageDriver statistics via registry iteration.
        let counters = Self.readDiskCounters()
        let now = Date()
        defer {
            previousReadBytes = counters.readBytes
            previousWriteBytes = counters.writeBytes
            previousReadOps = counters.readOps
            previousWriteOps = counters.writeOps
            previousTimestamp = now
        }

        guard let previousTimestamp else {
            return (0, 0, 0, 0)
        }
        let dt = now.timeIntervalSince(previousTimestamp)
        guard dt > 0 else { return (0, 0, 0, 0) }

        let readBps = Double(counters.readBytes &- previousReadBytes) / dt
        let writeBps = Double(counters.writeBytes &- previousWriteBytes) / dt
        let readOps = Double(counters.readOps &- previousReadOps) / dt
        let writeOps = Double(counters.writeOps &- previousWriteOps) / dt
        return (max(0, readBps), max(0, writeBps), max(0, readOps), max(0, writeOps))
    }

    private static func readDiskCounters() -> (readBytes: UInt64, writeBytes: UInt64, readOps: UInt64, writeOps: UInt64) {
        var readBytes: UInt64 = 0
        var writeBytes: UInt64 = 0
        var readOps: UInt64 = 0
        var writeOps: UInt64 = 0

        var port: mach_port_t = 0
        guard IOMasterPort(kIOMainPortDefault, &port) == KERN_SUCCESS else {
            return (0, 0, 0, 0)
        }

        guard let matching = IOServiceMatching("IOBlockStorageDriver") else {
            return (0, 0, 0, 0)
        }

        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(port, matching, &iterator) == KERN_SUCCESS else {
            return (0, 0, 0, 0)
        }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            var properties: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let dict = properties?.takeRetainedValue() as? [String: Any],
                  let stats = dict["Statistics"] as? [String: Any] else { continue }

            if let v = stats["Bytes (Read)"] as? UInt64 { readBytes &+= v }
            else if let v = stats["Bytes (Read)"] as? Int64 { readBytes &+= UInt64(max(0, v)) }
            if let v = stats["Bytes (Write)"] as? UInt64 { writeBytes &+= v }
            else if let v = stats["Bytes (Write)"] as? Int64 { writeBytes &+= UInt64(max(0, v)) }
            if let v = stats["Operations (Read)"] as? UInt64 { readOps &+= v }
            else if let v = stats["Operations (Read)"] as? Int64 { readOps &+= UInt64(max(0, v)) }
            if let v = stats["Operations (Write)"] as? UInt64 { writeOps &+= v }
            else if let v = stats["Operations (Write)"] as? Int64 { writeOps &+= UInt64(max(0, v)) }
        }

        return (readBytes, writeBytes, readOps, writeOps)
    }

    private static func enumerateVolumes() -> [StorageMetrics.VolumeInfo] {
        let keys: [URLResourceKey] = [
            .volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
            .volumeIsRootFileSystemKey, .volumeIsLocalKey
        ]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        var result: [StorageMetrics.VolumeInfo] = []

        for url in urls {
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            let total = UInt64(values.volumeTotalCapacity ?? 0)
            let free = UInt64(values.volumeAvailableCapacity ?? 0)
            guard total > 0 else { continue }
            let name = values.volumeName ?? url.lastPathComponent
            let isRoot = values.volumeIsRootFileSystem ?? false
            result.append(
                StorageMetrics.VolumeInfo(
                    name: name,
                    path: url.path,
                    totalBytes: total,
                    freeBytes: free,
                    isSSD: true,
                    isRoot: isRoot
                )
            )
        }
        return result.sorted { ($0.isRoot ? 0 : 1) < ($1.isRoot ? 0 : 1) }
    }
}

import Foundation
import Darwin

/// Collects VM statistics via `host_statistics64` and memory pressure via `DispatchSource`.
public actor MemoryService: MetricProviding {
    public typealias Metric = MemoryMetrics

    private var pressure: MemoryMetrics.MemoryPressure = .normal
    private var pressureSource: DispatchSourceMemoryPressure?

    public init() {
        Task { await self.startPressureMonitor() }
    }

    public func sample() async -> MemoryMetrics {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        let pageSize = UInt64(sysconf(Int32(_SC_PAGESIZE)))
        var total: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &total, &size, nil, 0)

        guard result == KERN_SUCCESS else {
            return MemoryMetrics.empty
        }

        let free = UInt64(stats.free_count) * pageSize
        let active = UInt64(stats.active_count) * pageSize
        let inactive = UInt64(stats.inactive_count) * pageSize
        let wired = UInt64(stats.wire_count) * pageSize
        let compressed = UInt64(stats.compressor_page_count) * pageSize
        let speculative = UInt64(stats.speculative_count) * pageSize
        let purgeable = UInt64(stats.purgeable_count) * pageSize
        let external = UInt64(stats.external_page_count) * pageSize

        let appMemory = active + inactive + speculative + wired + compressed
        let used = total > free ? total - free - speculative : active + wired + compressed
        let cached = purgeable + external

        let swap = Self.readSwap()

        return MemoryMetrics(
            totalBytes: total,
            usedBytes: min(used, total),
            freeBytes: free,
            activeBytes: active,
            inactiveBytes: inactive,
            wiredBytes: wired,
            compressedBytes: compressed,
            appMemoryBytes: min(appMemory, total),
            cachedBytes: cached,
            swapUsedBytes: swap.used,
            swapTotalBytes: swap.total,
            pressure: pressure,
            pageIns: UInt64(stats.pageins),
            pageOuts: UInt64(stats.pageouts),
            compressions: UInt64(stats.compressions),
            decompressions: UInt64(stats.decompressions)
        )
    }

    private func startPressureMonitor() {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical, .normal], queue: .global(qos: .utility))
        source.setEventHandler { [weak self] in
            let raw = source.data.rawValue
            Task { [weak self] in
                await self?.updatePressure(raw)
            }
        }
        source.resume()
        pressureSource = source
    }

    private func updatePressure(_ raw: UInt) {
        let event = DispatchSource.MemoryPressureEvent(rawValue: raw)
        if event.contains(.critical) {
            pressure = .critical
        } else if event.contains(.warning) {
            pressure = .warning
        } else {
            pressure = .normal
        }
    }

    private static func readSwap() -> (used: UInt64, total: UInt64) {
        var swapUsage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        let result = sysctlbyname("vm.swapusage", &swapUsage, &size, nil, 0)
        guard result == 0 else { return (0, 0) }
        return (UInt64(swapUsage.xsu_used), UInt64(swapUsage.xsu_total))
    }
}

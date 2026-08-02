import Foundation
import IOKit
import Metal

/// Reads GPU activity from the accelerator's published performance statistics.
///
/// Every `IOAccelerator` driver — AMD, Intel and Apple — maintains a
/// `PerformanceStatistics` dictionary in the IO registry. Those are the driver's
/// own counters, readable without entitlements, and they are the only public
/// source of GPU load on macOS; the `IOReport` channels Activity Monitor uses are
/// private. Depending on the driver they also carry core clock, die temperature
/// and package power.
///
/// The statistics are matched to the GPU Metal is actually using, via the
/// device's registry ID, so a laptop with switchable graphics reports the active
/// GPU instead of whichever accelerator happens to be listed first. Counters the
/// driver does not publish stay `nil` rather than being inferred from anything
/// else.
public actor GPUService: MetricProviding {
    public typealias Metric = GPUMetrics

    private var deviceName: String?
    private var memoryTotal: UInt64?
    private var statisticsEntry: io_registry_entry_t = IO_OBJECT_NULL

    public init() {}

    deinit {
        if statisticsEntry != IO_OBJECT_NULL { IOObjectRelease(statisticsEntry) }
    }

    public func sample() async -> GPUMetrics {
        if deviceName == nil { resolveDevice() }
        let stats = readStatistics()

        return GPUMetrics(
            utilization: stats.device,
            rendererUtilization: stats.renderer,
            tilerUtilization: stats.tiler,
            deviceUtilization: stats.device,
            frequencyMHz: stats.coreClockMHz,
            memoryUsedBytes: stats.memoryInUse,
            memoryTotalBytes: memoryTotal,
            powerWatts: stats.powerWatts,
            temperatureC: stats.temperatureC,
            deviceName: deviceName ?? "Unknown GPU",
            isMetalActive: statisticsEntry != IO_OBJECT_NULL
        )
    }

    // MARK: - Device resolution

    private func resolveDevice() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            deviceName = "No Metal device"
            return
        }
        deviceName = device.name
        memoryTotal = device.recommendedMaxWorkingSetSize

        let entry = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IORegistryEntryIDMatching(device.registryID)
        )
        guard entry != IO_OBJECT_NULL else { return }
        defer { IOObjectRelease(entry) }

        statisticsEntry = Self.findStatisticsProvider(from: entry, depth: 0) ?? IO_OBJECT_NULL
    }

    /// Walks down from the Metal device's registry entry to whichever node carries
    /// `PerformanceStatistics`. On some drivers that is the entry itself; on others
    /// it is a child accelerator node.
    private static func findStatisticsProvider(
        from entry: io_registry_entry_t,
        depth: Int
    ) -> io_registry_entry_t? {
        if hasStatistics(entry) {
            IOObjectRetain(entry)
            return entry
        }
        guard depth < 3 else { return nil }

        var children: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(entry, kIOServicePlane, &children) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(children) }

        while case let child = IOIteratorNext(children), child != IO_OBJECT_NULL {
            if let found = findStatisticsProvider(from: child, depth: depth + 1) {
                IOObjectRelease(child)
                return found
            }
            IOObjectRelease(child)
        }
        return nil
    }

    private static func hasStatistics(_ entry: io_registry_entry_t) -> Bool {
        guard let value = IORegistryEntryCreateCFProperty(
            entry, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0
        ) else { return false }
        return (value.takeRetainedValue() as? [String: Any]) != nil
    }

    // MARK: - Counters

    private struct Statistics {
        var device: Double?
        var renderer: Double?
        var tiler: Double?
        var memoryInUse: UInt64?
        var coreClockMHz: Double?
        var temperatureC: Double?
        var powerWatts: Double?
    }

    private func readStatistics() -> Statistics {
        var result = Statistics()
        guard statisticsEntry != IO_OBJECT_NULL,
              let raw = IORegistryEntryCreateCFProperty(
                statisticsEntry, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0
              ),
              let stats = raw.takeRetainedValue() as? [String: Any] else {
            return result
        }

        func number(_ key: String) -> Double? {
            (stats[key] as? NSNumber)?.doubleValue
        }

        result.device = number("Device Utilization %") ?? number("GPU Activity(%)")
        result.renderer = number("Renderer Utilization %")
        result.tiler = number("Tiler Utilization %")
        result.coreClockMHz = number("Core Clock(MHz)").flatMap { $0 > 0 ? $0 : nil }
        result.temperatureC = number("Temperature(C)").flatMap { $0 > 0 ? $0 : nil }
        result.powerWatts = number("Total Power(W)").flatMap { $0 > 0 ? $0 : nil }

        if let inUse = number("inUseVidMemoryBytes") ?? number("In use system memory"), inUse > 0 {
            result.memoryInUse = UInt64(inUse)
        }
        return result
    }
}

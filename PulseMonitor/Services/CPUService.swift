import Foundation
import Darwin

/// Collects CPU utilization via `host_processor_info`, load averages, and topology via sysctl.
public actor CPUService: MetricProviding {
    public typealias Metric = CPUMetrics

    private var previousTicks: [CPUTicks] = []
    private var previousHostCPU: host_cpu_load_info?
    private var previousTimestamp: Date?

    private struct CPUTicks {
        var user: UInt32
        var system: UInt32
        var idle: UInt32
        var nice: UInt32
    }

    public init() {}

    public func sample() async -> CPUMetrics {
        let topology = Self.readTopology()
        let load = Self.readLoadAverage()
        let brand = Self.readBrand()
        let architecture = Self.detectArchitecture()
        let (perCore, totals) = samplePerCore()
        let (pCores, eCores) = Self.splitPECores(perCore: perCore, pCount: topology.pCores, eCount: topology.eCores)
        let processThread = Self.readProcessThreadCounts()
        let vm = Self.readVMStats()

        let totalUsage = totals.total
        let isThrottling = Self.detectThrottling(usage: totalUsage, thermalState: ProcessInfo.processInfo.thermalState)

        return CPUMetrics(
            totalUsage: totalUsage,
            userUsage: totals.user,
            systemUsage: totals.system,
            idleUsage: totals.idle,
            niceUsage: totals.nice,
            perCoreUsage: perCore,
            performanceCoreUsage: pCores,
            efficiencyCoreUsage: eCores,
            performanceCoreCount: topology.pCores,
            efficiencyCoreCount: topology.eCores,
            logicalCoreCount: topology.logical,
            physicalCoreCount: topology.physical,
            currentFrequencyMHz: Self.readFrequencyMHz(),
            maxFrequencyMHz: Self.readMaxFrequencyMHz(),
            loadAverage1: load.0,
            loadAverage5: load.1,
            loadAverage15: load.2,
            processCount: processThread.processes,
            threadCount: processThread.threads,
            contextSwitches: vm.contextSwitches,
            interrupts: vm.interrupts,
            packagePowerWatts: nil,
            brand: brand,
            architecture: architecture,
            isThrottling: isThrottling
        )
    }

    private func samplePerCore() -> (perCore: [Double], totals: (total: Double, user: Double, system: Double, idle: Double, nice: Double)) {
        var cpuCount: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var cpuInfoCount: mach_msg_type_number_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &cpuCount,
            &cpuInfo,
            &cpuInfoCount
        )

        guard result == KERN_SUCCESS, let cpuInfo else {
            return ([], (0, 0, 0, 100, 0))
        }

        defer {
            let size = vm_size_t(cpuInfoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: cpuInfo), size)
        }

        var current: [CPUTicks] = []
        current.reserveCapacity(Int(cpuCount))

        for i in 0..<Int(cpuCount) {
            let offset = Int(CPU_STATE_MAX) * i
            let user = UInt32(cpuInfo[offset + Int(CPU_STATE_USER)])
            let system = UInt32(cpuInfo[offset + Int(CPU_STATE_SYSTEM)])
            let idle = UInt32(cpuInfo[offset + Int(CPU_STATE_IDLE)])
            let nice = UInt32(cpuInfo[offset + Int(CPU_STATE_NICE)])
            current.append(CPUTicks(user: user, system: system, idle: idle, nice: nice))
        }

        var perCore: [Double] = []
        var sumUser = 0.0, sumSystem = 0.0, sumIdle = 0.0, sumNice = 0.0, sumTotal = 0.0

        if previousTicks.count == current.count {
            for i in 0..<current.count {
                let dUser = Double(current[i].user &- previousTicks[i].user)
                let dSystem = Double(current[i].system &- previousTicks[i].system)
                let dIdle = Double(current[i].idle &- previousTicks[i].idle)
                let dNice = Double(current[i].nice &- previousTicks[i].nice)
                let total = dUser + dSystem + dIdle + dNice
                let usage = total > 0 ? ((dUser + dSystem + dNice) / total) * 100.0 : 0
                perCore.append(min(100, max(0, usage)))
                sumUser += dUser
                sumSystem += dSystem
                sumIdle += dIdle
                sumNice += dNice
                sumTotal += total
            }
        } else {
            perCore = Array(repeating: 0, count: current.count)
        }

        previousTicks = current

        let scale = sumTotal > 0 ? 100.0 / sumTotal : 0
        return (
            perCore,
            (
                total: min(100, max(0, (sumUser + sumSystem + sumNice) * scale)),
                user: sumUser * scale,
                system: sumSystem * scale,
                idle: sumIdle * scale,
                nice: sumNice * scale
            )
        )
    }

    private static func splitPECores(perCore: [Double], pCount: Int, eCount: Int) -> ([Double], [Double]) {
        guard !perCore.isEmpty else { return ([], []) }
        // On Apple Silicon, performance cores are typically listed first.
        if pCount > 0 || eCount > 0 {
            let p = Array(perCore.prefix(pCount))
            let e = Array(perCore.dropFirst(pCount).prefix(eCount))
            return (p, e)
        }
        return (perCore, [])
    }

    private static func readTopology() -> (logical: Int, physical: Int, pCores: Int, eCores: Int) {
        var logical: Int32 = 0
        var physical: Int32 = 0
        var size = MemoryLayout<Int32>.size
        sysctlbyname("hw.logicalcpu", &logical, &size, nil, 0)
        size = MemoryLayout<Int32>.size
        sysctlbyname("hw.physicalcpu", &physical, &size, nil, 0)

        var pCores: Int32 = 0
        var eCores: Int32 = 0
        size = MemoryLayout<Int32>.size
        if sysctlbyname("hw.perflevel0.logicalcpu", &pCores, &size, nil, 0) != 0 {
            pCores = 0
        }
        size = MemoryLayout<Int32>.size
        if sysctlbyname("hw.perflevel1.logicalcpu", &eCores, &size, nil, 0) != 0 {
            eCores = 0
        }

        if pCores == 0 && eCores == 0 {
            pCores = logical
        }

        return (Int(logical), Int(physical), Int(pCores), Int(eCores))
    }

    private static func readLoadAverage() -> (Double, Double, Double) {
        var load: [Double] = [0, 0, 0]
        getloadavg(&load, 3)
        return (load[0], load[1], load[2])
    }

    private static func readBrand() -> String {
        if let brand = Sysctl.string("machdep.cpu.brand_string") { return brand }
        // Apple Silicon does not expose machdep.cpu.brand_string; hw.model is the
        // closest public equivalent.
        if let model = Sysctl.string("hw.model") { return model }
        #if arch(arm64)
        return "Apple Silicon"
        #else
        return "Intel CPU"
        #endif
    }

    private static func detectArchitecture() -> CPUMetrics.CPUArchitecture {
        #if arch(arm64)
        return .appleSilicon
        #elseif arch(x86_64)
        return .intel
        #else
        return .unknown
        #endif
    }

    private static func readFrequencyMHz() -> Double? {
        var freq: Int64 = 0
        var size = MemoryLayout<Int64>.size
        if sysctlbyname("hw.cpufrequency", &freq, &size, nil, 0) == 0, freq > 0 {
            return Double(freq) / 1_000_000.0
        }
        return nil
    }

    private static func readMaxFrequencyMHz() -> Double? {
        var freq: Int64 = 0
        var size = MemoryLayout<Int64>.size
        if sysctlbyname("hw.cpufrequency_max", &freq, &size, nil, 0) == 0, freq > 0 {
            return Double(freq) / 1_000_000.0
        }
        return readFrequencyMHz()
    }

    /// Live task and thread totals from the default processor set — the same
    /// source `top` reports. Unlike counting `proc_listallpids` this needs no
    /// per-process syscall, so it is cheap enough to run every tick.
    private static func readProcessThreadCounts() -> (processes: Int, threads: Int) {
        var pset = processor_set_name_t()
        guard processor_set_default(mach_host_self(), &pset) == KERN_SUCCESS else {
            return (0, 0)
        }
        defer { mach_port_deallocate(mach_task_self_, pset) }

        var info = processor_set_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<processor_set_load_info>.stride / MemoryLayout<natural_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                processor_set_statistics(pset, PROCESSOR_SET_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (0, 0) }
        return (processes: Int(info.task_count), threads: Int(info.thread_count))
    }

    private static func readVMStats() -> (contextSwitches: UInt64, interrupts: UInt64) {
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        var vmstat = vm_statistics64()
        let result = withUnsafeMutablePointer(to: &vmstat) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (0, 0) }
        // vm_statistics64 does not expose context switches directly on all SDKs;
        // leave zeros when unavailable (Process/host stats fill gaps).
        return (0, 0)
    }

    private static func detectThrottling(usage: Double, thermalState: ProcessInfo.ThermalState) -> Bool {
        thermalState == .serious || thermalState == .critical
    }
}

import Foundation

/// Rule-based analysis engine that diagnoses bottlenecks and explains them in plain English.
public actor BottleneckEngine: AnalysisEngine {
    public init() {}

    public func analyze(
        metrics: SystemMetrics,
        processes: [ProcessInfoModel],
        previous: SystemMetrics?
    ) async -> AnalysisReport {
        var findings: [BottleneckFinding] = []
        let topCPU = Array(processes.sorted { $0.cpuPercent > $1.cpuPercent }.prefix(5))
        let topMem = Array(processes.sorted { $0.memoryBytes > $1.memoryBytes }.prefix(5))

        findings += diagnoseCPU(metrics: metrics, top: topCPU)
        findings += diagnoseGPU(metrics: metrics, processes: processes)
        findings += diagnoseMemory(metrics: metrics, previous: previous, top: topMem)
        findings += diagnoseThermal(metrics: metrics)
        findings += diagnoseStorage(metrics: metrics)
        findings += diagnoseNetwork(metrics: metrics, previous: previous)
        findings += diagnoseBattery(metrics: metrics, processes: processes)
        findings += diagnoseScheduling(metrics: metrics, processes: processes)

        findings.sort { $0.severity > $1.severity }
        let primary = findings.first
        let score = healthScore(metrics: metrics, findings: findings)
        let narrative = ExplanationGenerator.narrative(primary: primary, metrics: metrics, topCPU: topCPU)

        return AnalysisReport(
            timestamp: .now,
            findings: findings,
            primaryBottleneck: primary,
            overallHealthScore: score,
            narrative: narrative
        )
    }

    private func diagnoseCPU(metrics: SystemMetrics, top: [ProcessInfoModel]) -> [BottleneckFinding] {
        var findings: [BottleneckFinding] = []
        let cpu = metrics.cpu
        let gpu = metrics.gpu

        // The comparative claim needs a real GPU reading. Where the driver
        // publishes no counter, an unknown GPU is not evidence of an idle one, so
        // the rule falls through to the plain high-load finding below.
        if cpu.totalUsage > 95, let gpuLoad = gpu.utilization, gpuLoad < 40 {
            let leader = top.first
            let detail = ExplanationGenerator.cpuBottleneckDetail(cpu: cpu, leader: leader)
            findings.append(
                BottleneckFinding(
                    id: UUID(),
                    category: .cpu,
                    severity: .critical,
                    title: "CPU Bottleneck",
                    summary: "Your CPU is the current limiting component while the GPU remains relatively idle.",
                    detail: detail,
                    relatedProcesses: top.map(\.name),
                    recommendations: [
                        "Close or throttle the top CPU consumers listed above.",
                        "Check for runaway background helpers and launch agents.",
                        cpu.architecture == .appleSilicon
                            ? "If a game or simulator is P-core bound, reduce simulation distance, entity counts, or mods."
                            : "Reduce thread contention and background indexing (Spotlight, Time Machine, antivirus)."
                    ],
                    detectedAt: .now,
                    confidence: 0.9
                )
            )
        } else if cpu.systemUsage > 40 && cpu.userUsage < 30 {
            findings.append(
                BottleneckFinding(
                    id: UUID(),
                    category: .cpu,
                    severity: .warning,
                    title: "Kernel Overload",
                    summary: "A large share of CPU time is spent in the kernel/system rather than user apps.",
                    detail: "High system time often points to drivers, filesystem pressure, virtualization, or aggressive interrupt activity.",
                    relatedProcesses: top.map(\.name),
                    recommendations: [
                        "Inspect Disk and Network modules for I/O storms.",
                        "Check newly installed kernel extensions / system extensions.",
                        "Look for antivirus or backup tools scanning aggressively."
                    ],
                    detectedAt: .now,
                    confidence: 0.75
                )
            )
        } else if cpu.totalUsage > 80 {
            findings.append(
                BottleneckFinding(
                    id: UUID(),
                    category: .cpu,
                    severity: .warning,
                    title: "High CPU Load",
                    summary: String(format: "CPU utilization is elevated at %.0f%%.", cpu.totalUsage),
                    detail: ExplanationGenerator.cpuBottleneckDetail(cpu: cpu, leader: top.first),
                    relatedProcesses: top.map(\.name),
                    recommendations: ["Identify the top processes and quit non-essential ones."],
                    detectedAt: .now,
                    confidence: 0.7
                )
            )
        }

        if !cpu.efficiencyCoreUsage.isEmpty {
            let eAvg = cpu.efficiencyCoreUsage.reduce(0, +) / Double(cpu.efficiencyCoreUsage.count)
            let pAvg = cpu.performanceCoreUsage.isEmpty ? 0 :
                cpu.performanceCoreUsage.reduce(0, +) / Double(cpu.performanceCoreUsage.count)
            if eAvg > 85 && pAvg < 40 {
                findings.append(
                    BottleneckFinding(
                        id: UUID(),
                        category: .cpu,
                        severity: .info,
                        title: "Background Overload on Efficiency Cores",
                        summary: "Efficiency cores are saturated while performance cores are relatively free.",
                        detail: "This usually indicates many background tasks rather than a foreground interactive workload.",
                        relatedProcesses: top.map(\.name),
                        recommendations: ["Review Login Items and background agents in System Settings."],
                        detectedAt: .now,
                        confidence: 0.65
                    )
                )
            }
        }
        return findings
    }

    private func diagnoseGPU(metrics: SystemMetrics, processes: [ProcessInfoModel]) -> [BottleneckFinding] {
        var findings: [BottleneckFinding] = []
        if let gpuLoad = metrics.gpu.utilization, gpuLoad > 95, metrics.cpu.totalUsage < 60 {
            findings.append(
                BottleneckFinding(
                    id: UUID(),
                    category: .gpu,
                    severity: .critical,
                    title: "GPU Bottleneck",
                    summary: "The GPU is saturated while the CPU still has headroom.",
                    detail: "Rendering or compute work is likely the limiter. WindowServer abuse, high-resolution displays, or Metal-heavy apps are common causes.",
                    relatedProcesses: processes.filter { $0.name.contains("WindowServer") || $0.isGame }.map(\.name),
                    recommendations: [
                        "Lower resolution/refresh rate or graphics quality.",
                        "Check for WindowServer CPU spikes with many external displays.",
                        "Disable expensive visual effects during heavy workloads."
                    ],
                    detectedAt: .now,
                    confidence: 0.85
                )
            )
        }
        // A WindowServer rule used to live here. It could never fire: WindowServer
        // runs as another user, and task info for such a process is unreadable
        // without root, so its CPU share never reached this engine.
        return findings
    }

    private func diagnoseMemory(metrics: SystemMetrics, previous: SystemMetrics?, top: [ProcessInfoModel]) -> [BottleneckFinding] {
        var findings: [BottleneckFinding] = []
        let mem = metrics.memory

        if mem.pressure == .critical || (mem.swapUsedBytes > 1_073_741_824 && mem.usagePercent > 85) {
            findings.append(
                BottleneckFinding(
                    id: UUID(),
                    category: .memory,
                    severity: .critical,
                    title: "Memory Bottleneck",
                    summary: "Memory pressure is high and the system may be swapping.",
                    detail: "Heavy compression and swap activity stall interactive performance even when CPU looks free.",
                    relatedProcesses: top.map(\.name),
                    recommendations: [
                        "Quit the largest memory consumers.",
                        "Avoid opening additional browser profiles or VMs.",
                        "Consider more unified/physical memory for this workload."
                    ],
                    detectedAt: .now,
                    confidence: 0.9
                )
            )
        }

        if let previous {
            let swapDelta = Double(mem.swapUsedBytes) - Double(previous.memory.swapUsedBytes)
            if swapDelta > 50_000_000 {
                findings.append(
                    BottleneckFinding(
                        id: UUID(),
                        category: .memory,
                        severity: .warning,
                        title: "Swap Storm",
                        summary: "Swap usage is increasing rapidly.",
                        detail: String(format: "Swap grew by %@ since the last sample.", Formatters.bytes(UInt64(max(0, swapDelta)))),
                        relatedProcesses: top.map(\.name),
                        recommendations: ["Free memory immediately to stop thrashing."],
                        detectedAt: .now,
                        confidence: 0.8
                    )
                )
            }
        }

        if mem.compressedBytes > mem.totalBytes / 4 {
            findings.append(
                BottleneckFinding(
                    id: UUID(),
                    category: .memory,
                    severity: .warning,
                    title: "Heavy Memory Compression",
                    summary: "A large portion of memory is compressed.",
                    detail: "Compression is cheaper than swap but still burns CPU and adds latency.",
                    relatedProcesses: top.map(\.name),
                    recommendations: ["Reduce resident working sets of the top apps."],
                    detectedAt: .now,
                    confidence: 0.7
                )
            )
        }
        return findings
    }

    private func diagnoseThermal(metrics: SystemMetrics) -> [BottleneckFinding] {
        var findings: [BottleneckFinding] = []
        if metrics.thermal.isThrottling || metrics.cpu.isThrottling {
            findings.append(
                BottleneckFinding(
                    id: UUID(),
                    category: .thermal,
                    severity: .critical,
                    title: "Thermally Throttled",
                    summary: "Temperature pressure is reducing performance.",
                    detail: metrics.thermal.throttleReason
                        ?? "Frequency is being limited to protect hardware. Sustained load, blocked vents, or high ambient temperature are common causes.",
                    relatedProcesses: [],
                    recommendations: [
                        "Elevate the Mac for airflow and clear vents.",
                        "Reduce sustained workload intensity.",
                        "Check for dust accumulation if throttling is frequent."
                    ],
                    detectedAt: .now,
                    confidence: 0.88
                )
            )
        } else if metrics.thermal.thermalState == .fair {
            findings.append(
                BottleneckFinding(
                    id: UUID(),
                    category: .thermal,
                    severity: .info,
                    title: "Elevated Thermal State",
                    summary: "Thermal pressure is above nominal.",
                    detail: "Performance may begin to taper if load continues.",
                    relatedProcesses: [],
                    recommendations: ["Monitor temperatures; reduce load if you need sustained peak clocks."],
                    detectedAt: .now,
                    confidence: 0.6
                )
            )
        }
        return findings
    }

    private func diagnoseStorage(metrics: SystemMetrics) -> [BottleneckFinding] {
        var findings: [BottleneckFinding] = []
        if let root = metrics.storage.volumes.first(where: \.isRoot) {
            if root.usedPercent > 95 {
                findings.append(
                    BottleneckFinding(
                        id: UUID(),
                        category: .storage,
                        severity: .critical,
                        title: "Storage Nearly Full",
                        summary: String(format: "Boot volume is %.0f%% full.", root.usedPercent),
                        detail: "Low free space degrades SSD performance and can stall swap/compaction.",
                        relatedProcesses: [],
                        recommendations: ["Free at least 15–20% of the volume.", "Clear large downloads, caches, and old VMs."],
                        detectedAt: .now,
                        confidence: 0.95
                    )
                )
            } else if root.usedPercent > 90 {
                findings.append(
                    BottleneckFinding(
                        id: UUID(),
                        category: .storage,
                        severity: .warning,
                        title: "Low Free Space",
                        summary: String(format: "Boot volume is %.0f%% full.", root.usedPercent),
                        detail: "SSD controllers need spare area for efficient garbage collection.",
                        relatedProcesses: [],
                        recommendations: ["Free space soon to avoid performance cliffs."],
                        detectedAt: .now,
                        confidence: 0.85
                    )
                )
            }
        }

        let io = metrics.storage.readBytesPerSec + metrics.storage.writeBytesPerSec
        if io > 400_000_000 && metrics.cpu.totalUsage < 70 {
            findings.append(
                BottleneckFinding(
                    id: UUID(),
                    category: .storage,
                    severity: .warning,
                    title: "Disk Bottleneck",
                    summary: "Disk throughput is very high and may be limiting responsiveness.",
                    detail: String(format: "Combined disk I/O is %@.", Formatters.bytesPerSecond(io)),
                    relatedProcesses: [],
                    recommendations: ["Identify apps writing heavily (backups, sync, video export).", "Pause cloud sync temporarily."],
                    detectedAt: .now,
                    confidence: 0.7
                )
            )
        }
        return findings
    }

    private func diagnoseNetwork(metrics: SystemMetrics, previous: SystemMetrics?) -> [BottleneckFinding] {
        var findings: [BottleneckFinding] = []
        let total = metrics.network.bytesInPerSec + metrics.network.bytesOutPerSec
        if total > 50_000_000 {
            findings.append(
                BottleneckFinding(
                    id: UUID(),
                    category: .network,
                    severity: .info,
                    title: "Network Saturated / Busy",
                    summary: "Network throughput is high.",
                    detail: "Cloud sync, streaming, or large downloads may compete with interactive apps and games.",
                    relatedProcesses: [],
                    recommendations: ["Pause cloud sync clients if you need low latency.", "Prefer wired Ethernet for large transfers."],
                    detectedAt: .now,
                    confidence: 0.6
                )
            )
        }
        return findings
    }

    private func diagnoseBattery(metrics: SystemMetrics, processes: [ProcessInfoModel]) -> [BottleneckFinding] {
        var findings: [BottleneckFinding] = []
        guard metrics.battery.isPresent else { return findings }
        if let health = metrics.battery.healthPercent, health < 80 {
            findings.append(
                BottleneckFinding(
                    id: UUID(),
                    category: .battery,
                    severity: .warning,
                    title: "Battery Degradation",
                    summary: String(format: "Battery health is about %.0f%%.", health),
                    detail: "Aged batteries can cause earlier power throttling under load.",
                    relatedProcesses: [],
                    recommendations: ["Consider battery service if runtime or peak power is unacceptable."],
                    detectedAt: .now,
                    confidence: 0.8
                )
            )
        }
        if metrics.battery.powerSource == .battery && metrics.cpu.totalUsage > 70 {
            let hungry = processes.filter { $0.cpuPercent > 20 }.prefix(3).map(\.name)
            findings.append(
                BottleneckFinding(
                    id: UUID(),
                    category: .battery,
                    severity: .info,
                    title: "High Drain on Battery",
                    summary: "Significant CPU load while on battery power.",
                    detail: "Power-hungry processes shorten runtime and raise thermals.",
                    relatedProcesses: Array(hungry),
                    recommendations: ["Plug in for sustained performance.", "Enable Low Power Mode for longevity."],
                    detectedAt: .now,
                    confidence: 0.65
                )
            )
        }
        return findings
    }

    private func diagnoseScheduling(metrics: SystemMetrics, processes: [ProcessInfoModel]) -> [BottleneckFinding] {
        let threadHeavy = processes.filter { $0.threadCount > 150 }.prefix(3)
        guard !threadHeavy.isEmpty, metrics.cpu.loadAverage1 > Double(metrics.cpu.logicalCoreCount) else { return [] }
        return [
            BottleneckFinding(
                id: UUID(),
                category: .system,
                severity: .info,
                title: "Possible Poor Thread Scheduling",
                summary: "Load average exceeds core count while some processes own huge thread pools.",
                detail: "Excessive threads can cause contention and context-switch overhead.",
                relatedProcesses: threadHeavy.map(\.name),
                recommendations: ["Update the offending app.", "Reduce parallel workers if configurable."],
                detectedAt: .now,
                confidence: 0.55
            )
        ]
    }

    private func healthScore(metrics: SystemMetrics, findings: [BottleneckFinding]) -> Double {
        var score = 100.0
        for finding in findings {
            switch finding.severity {
            case .critical: score -= 18
            case .warning: score -= 8
            case .info: score -= 3
            }
        }
        score -= metrics.cpu.totalUsage * 0.05
        score -= metrics.memory.usagePercent * 0.05
        if metrics.thermal.isThrottling { score -= 15 }
        return min(100, max(0, score))
    }
}

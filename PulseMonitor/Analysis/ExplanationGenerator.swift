import Foundation

/// Produces human-readable explanations for bottleneck findings.
public enum ExplanationGenerator {
    public static func narrative(
        primary: BottleneckFinding?,
        metrics: SystemMetrics,
        topCPU: [ProcessInfoModel]
    ) -> String {
        guard let primary else {
            return "System looks balanced. No dominant bottleneck detected. CPU \(Formatters.percent(metrics.cpu.totalUsage)), memory \(Formatters.percent(metrics.memory.usagePercent)), GPU \(Formatters.percent(metrics.gpu.utilization))."
        }

        let leader = topCPU.first
        switch primary.category {
        case .cpu:
            return cpuBottleneckDetail(cpu: metrics.cpu, leader: leader)
        case .gpu:
            return "Your GPU is the current limiting component (\(Formatters.percent(metrics.gpu.utilization)) busy) while the CPU still has headroom (\(Formatters.percent(metrics.cpu.totalUsage))). This usually indicates rendering saturation, Metal inefficiency, or WindowServer composition pressure."
        case .memory:
            return "Memory pressure is limiting responsiveness. Used \(Formatters.percent(metrics.memory.usagePercent)), compressed \(Formatters.bytes(metrics.memory.compressedBytes)), swap \(Formatters.bytes(metrics.memory.swapUsedBytes))."
        case .thermal:
            return primary.detail
        case .storage:
            return primary.detail
        case .network:
            return primary.detail
        case .battery:
            return primary.detail
        case .game:
            return primary.detail
        case .system:
            return primary.detail
        }
    }

    public static func cpuBottleneckDetail(cpu: CPUMetrics, leader: ProcessInfoModel?) -> String {
        var parts: [String] = []
        parts.append("Your CPU is the current limiting component at \(Formatters.percent(cpu.totalUsage)).")

        if cpu.architecture == .appleSilicon,
           !cpu.performanceCoreUsage.isEmpty {
            let pAvg = cpu.performanceCoreUsage.reduce(0, +) / Double(cpu.performanceCoreUsage.count)
            let eAvg = cpu.efficiencyCoreUsage.isEmpty ? 0 :
                cpu.efficiencyCoreUsage.reduce(0, +) / Double(cpu.efficiencyCoreUsage.count)
            parts.append(String(format: "Performance cores average %.0f%% while efficiency cores average %.0f%%.", pAvg, eAvg))
        }

        if let leader {
            parts.append("\(leader.name) is using \(Formatters.percent(leader.cpuPercent, digits: 0)) CPU.")
            if GameDetector.isLikelyGame(name: leader.name, path: leader.executablePath, bundleID: leader.bundleIdentifier) {
                parts.append(gameSpecificAdvice(for: leader.name))
            }
        }

        if cpu.isThrottling {
            parts.append("Thermal or power throttling is also active, which further reduces available performance.")
        }

        return parts.joined(separator: " ")
    }

    public static func gameSpecificAdvice(for name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("minecraft") || lower.contains("java") {
            return "This usually indicates simulation distance, entity count, mods, Java garbage collection, or insufficient multithreading. GPU remaining idle supports a CPU-bound simulation."
        }
        if lower.contains("steam") || lower.contains("wine") || lower.contains("whisky") || lower.contains("crossover") {
            return "Translation/compatibility layers can amplify single-thread CPU bottlenecks even when the GPU has spare capacity."
        }
        if lower.contains("ryujinx") || lower.contains("rpcs3") || lower.contains("pcsx2") || lower.contains("dolphin") || lower.contains("cemu") || lower.contains("yuzu") || lower.contains("suyu") {
            return "Emulators are often CPU-bound due to recompilation and synchronization; lowering resolution helps less than lowering accurate emulation options."
        }
        return "If this is a game, check whether the workload is simulation-heavy (CPU) versus fill-rate/shader-heavy (GPU)."
    }
}

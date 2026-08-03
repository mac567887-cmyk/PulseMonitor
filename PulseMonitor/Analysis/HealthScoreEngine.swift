import Foundation

/// Multi-category system health score (0–100) with explainable deltas.
public struct HealthCategoryScore: Sendable, Codable, Equatable, Identifiable {
    public var id: String { category.rawValue }
    public let category: Category
    public let score: Double
    public let summary: String
    public let available: Bool

    public enum Category: String, CaseIterable, Sendable, Codable, Identifiable {
        case cpu, gpu, battery, storage, memory, cooling, network, power, security, software

        public var id: String { rawValue }
        public var displayName: String { rawValue.capitalized }
        public var symbol: String {
            switch self {
            case .cpu: "cpu"
            case .gpu: "cube"
            case .battery: "battery.100"
            case .storage: "internaldrive"
            case .memory: "memorychip"
            case .cooling: "fan"
            case .network: "network"
            case .power: "bolt.fill"
            case .security: "lock.shield"
            case .software: "app.badge.checkmark"
            }
        }
    }
}

public struct HealthScoreReport: Sendable, Codable, Equatable {
    public let timestamp: Date
    public let overall: Double
    public let categories: [HealthCategoryScore]
    public let changeReasons: [String]
    public let previousOverall: Double?

    public var delta: Double? {
        guard let previousOverall else { return nil }
        return overall - previousOverall
    }
}

/// Builds a transparent health score from live metrics — never invents missing sensors.
public struct HealthScoreEngine: Sendable {
    public init() {}

    public func evaluate(
        metrics: SystemMetrics,
        processes: [ProcessInfoModel],
        findings: [BottleneckFinding],
        previous: HealthScoreReport?
    ) -> HealthScoreReport {
        let categories: [HealthCategoryScore] = [
            scoreCPU(metrics),
            scoreGPU(metrics),
            scoreBattery(metrics),
            scoreStorage(metrics),
            scoreMemory(metrics),
            scoreCooling(metrics),
            scoreNetwork(metrics),
            scorePower(metrics),
            scoreSecurity(processes),
            scoreSoftware(findings)
        ]

        let available = categories.filter(\.available)
        let overall = available.isEmpty
            ? 100
            : available.map(\.score).reduce(0, +) / Double(available.count)

        var reasons: [String] = []
        if let previous {
            let delta = overall - previous.overall
            if abs(delta) >= 1 {
                reasons.append(String(format: "Overall health %@%.0f points.", delta >= 0 ? "+" : "", delta))
            }
            for category in categories {
                guard let old = previous.categories.first(where: { $0.category == category.category }),
                      category.available, old.available else { continue }
                let d = category.score - old.score
                if abs(d) >= 5 {
                    reasons.append("\(category.category.displayName): \(category.summary) (\(String(format: "%+.0f", d))).")
                }
            }
        }
        if reasons.isEmpty {
            reasons.append("Score reflects current load, thermals, storage headroom and finding severity.")
        }

        return HealthScoreReport(
            timestamp: .now,
            overall: min(100, max(0, overall)),
            categories: categories,
            changeReasons: reasons,
            previousOverall: previous?.overall
        )
    }

    private func scoreCPU(_ m: SystemMetrics) -> HealthCategoryScore {
        var score = 100 - m.cpu.totalUsage * 0.55
        if m.cpu.systemUsage > 35 { score -= 10 }
        return HealthCategoryScore(
            category: .cpu,
            score: clamp(score),
            summary: String(format: "Load %.0f%% · system %.0f%%", m.cpu.totalUsage, m.cpu.systemUsage),
            available: true
        )
    }

    private func scoreGPU(_ m: SystemMetrics) -> HealthCategoryScore {
        guard let util = m.gpu.utilization else {
            return HealthCategoryScore(
                category: .gpu,
                score: 100,
                summary: "Driver does not publish utilization — category omitted from average.",
                available: false
            )
        }
        return HealthCategoryScore(
            category: .gpu,
            score: clamp(100 - util * 0.45),
            summary: String(format: "Utilization %.0f%%", util),
            available: true
        )
    }

    private func scoreBattery(_ m: SystemMetrics) -> HealthCategoryScore {
        guard m.battery.isPresent else {
            return HealthCategoryScore(category: .battery, score: 100, summary: "Desktop / no battery.", available: false)
        }
        var score = 100.0
        if let health = m.battery.healthPercent {
            score = health
            if health < 80 { score -= 10 }
        } else {
            return HealthCategoryScore(
                category: .battery,
                score: 100,
                summary: "Health not published by SMC.",
                available: false
            )
        }
        if let cycles = m.battery.cycleCount, cycles > 1000 { score -= 8 }
        return HealthCategoryScore(
            category: .battery,
            score: clamp(score),
            summary: Formatters.percent(m.battery.healthPercent) + " health",
            available: true
        )
    }

    private func scoreStorage(_ m: SystemMetrics) -> HealthCategoryScore {
        let root = m.storage.volumes.first(where: \.isRoot) ?? m.storage.volumes.first
        guard let root else {
            return HealthCategoryScore(category: .storage, score: 100, summary: "No volume data.", available: false)
        }
        var score = 100 - root.usedPercent * 0.7
        if m.storage.smartHealth == .failing { score -= 40 }
        return HealthCategoryScore(
            category: .storage,
            score: clamp(score),
            summary: String(format: "%.0f%% used · %@", root.usedPercent, m.storage.smartHealth.displayName),
            available: true
        )
    }

    private func scoreMemory(_ m: SystemMetrics) -> HealthCategoryScore {
        var score = 100 - m.memory.usagePercent * 0.5
        switch m.memory.pressure {
        case .critical: score -= 25
        case .warning: score -= 12
        case .normal: break
        }
        if m.memory.swapUsedBytes > 2_000_000_000 { score -= 10 }
        return HealthCategoryScore(
            category: .memory,
            score: clamp(score),
            summary: "\(Formatters.percent(m.memory.usagePercent)) · \(m.memory.pressure.displayName)",
            available: true
        )
    }

    private func scoreCooling(_ m: SystemMetrics) -> HealthCategoryScore {
        var score = 100.0
        if m.thermal.isThrottling { score -= 35 }
        switch m.thermal.thermalState {
        case .nominal: break
        case .fair: score -= 10
        case .serious: score -= 25
        case .critical: score -= 45
        }
        if let t = m.thermal.cpuTemperatureC {
            if t > 95 { score -= 20 }
            else if t > 85 { score -= 10 }
        }
        return HealthCategoryScore(
            category: .cooling,
            score: clamp(score),
            summary: m.thermal.thermalState.displayName + (m.thermal.isThrottling ? " · throttling" : ""),
            available: true
        )
    }

    private func scoreNetwork(_ m: SystemMetrics) -> HealthCategoryScore {
        // Without packet-loss counters we only flag extreme sustained throughput.
        let total = m.network.bytesInPerSec + m.network.bytesOutPerSec
        let score = total > 100_000_000 ? 85.0 : 100.0
        return HealthCategoryScore(
            category: .network,
            score: score,
            summary: "↓ \(Formatters.bytesPerSecond(m.network.bytesInPerSec)) · ↑ \(Formatters.bytesPerSecond(m.network.bytesOutPerSec))",
            available: true
        )
    }

    private func scorePower(_ m: SystemMetrics) -> HealthCategoryScore {
        if m.power.isEstimated && m.power.totalSystemWatts <= 0 {
            return HealthCategoryScore(
                category: .power,
                score: 100,
                summary: "Package power not published on this Mac.",
                available: false
            )
        }
        var score = 100.0
        if m.power.totalSystemWatts > 80 { score -= 15 }
        return HealthCategoryScore(
            category: .power,
            score: clamp(score),
            summary: Formatters.watts(m.power.totalSystemWatts),
            available: true
        )
    }

    private func scoreSecurity(_ processes: [ProcessInfoModel]) -> HealthCategoryScore {
        let invalid = processes.filter { $0.codeSignatureStatus == "Invalid" }.count
        var score = 100.0
        if invalid > 0 { score -= Double(min(invalid, 5)) * 8 }
        return HealthCategoryScore(
            category: .security,
            score: clamp(score),
            summary: invalid == 0 ? "No invalid signatures in visible processes." : "\(invalid) invalid signature(s).",
            available: true
        )
    }

    private func scoreSoftware(_ findings: [BottleneckFinding]) -> HealthCategoryScore {
        var score = 100.0
        for finding in findings {
            switch finding.severity {
            case .critical: score -= 12
            case .warning: score -= 6
            case .info: score -= 2
            }
        }
        return HealthCategoryScore(
            category: .software,
            score: clamp(score),
            summary: findings.isEmpty ? "No active findings." : "\(findings.count) active finding(s).",
            available: true
        )
    }

    private func clamp(_ value: Double) -> Double { min(100, max(0, value)) }
}

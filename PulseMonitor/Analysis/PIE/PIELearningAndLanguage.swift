import Foundation

/// Local-only habit learning. Never leaves the device.
public struct PIEHabitProfile: Sendable, Codable, Equatable {
    public var typicalCPUPercent: Double?
    public var typicalCPUTempC: Double?
    public var typicalMemoryPercent: Double?
    public var typicalBatteryDrainPerHour: Double?
    public var commonProcessNames: [String]
    public var gamingHourHistogram: [Int: Int] // hour 0-23 → counts
    public var sampleCount: Int
    public var updatedAt: Date

    public static let empty = PIEHabitProfile(
        typicalCPUPercent: nil,
        typicalCPUTempC: nil,
        typicalMemoryPercent: nil,
        typicalBatteryDrainPerHour: nil,
        commonProcessNames: [],
        gamingHourHistogram: [:],
        sampleCount: 0,
        updatedAt: .distantPast
    )
}

public struct PIELearningModule: Sendable {
    private let storeURL: URL

    public init(storeURL: URL? = nil) {
        if let storeURL {
            self.storeURL = storeURL
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("PulseMonitor", isDirectory: true)
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            self.storeURL = base.appendingPathComponent("pie-habits.json")
        }
    }

    public func load() -> PIEHabitProfile {
        guard let data = try? Data(contentsOf: storeURL),
              let profile = try? JSONDecoder().decode(PIEHabitProfile.self, from: data) else {
            return .empty
        }
        return profile
    }

    public func observe(
        metrics: SystemMetrics,
        processes: [ProcessInfoModel],
        games: [ProcessInfoModel],
        learningEnabled: Bool
    ) -> PIEHabitProfile {
        guard learningEnabled else { return load() }
        var profile = load()
        let n = Double(max(profile.sampleCount, 1))

        func ema(_ previous: Double?, _ value: Double) -> Double {
            guard let previous else { return value }
            return previous * (n / (n + 1)) + value / (n + 1)
        }

        profile.typicalCPUPercent = ema(profile.typicalCPUPercent, metrics.cpu.totalUsage)
        profile.typicalMemoryPercent = ema(profile.typicalMemoryPercent, metrics.memory.usagePercent)
        if let temp = metrics.thermal.cpuTemperatureC {
            profile.typicalCPUTempC = ema(profile.typicalCPUTempC, temp)
        }

        let names = processes.sorted { $0.cpuPercent > $1.cpuPercent }.prefix(8).map(\.name)
        var counts: [String: Int] = Dictionary(uniqueKeysWithValues: profile.commonProcessNames.map { ($0, 1) })
        for name in names { counts[name, default: 0] += 1 }
        profile.commonProcessNames = counts.sorted { $0.value > $1.value }.prefix(24).map(\.key)

        if !games.isEmpty {
            let hour = Calendar.current.component(.hour, from: metrics.timestamp)
            profile.gamingHourHistogram[hour, default: 0] += 1
        }

        profile.sampleCount += 1
        profile.updatedAt = .now
        if let data = try? JSONEncoder().encode(profile) {
            try? data.write(to: storeURL, options: .atomic)
        }
        return profile
    }
}

public struct PIENaturalLanguageModule: Sendable {
    public init() {}

    public func answer(
        question: String,
        metrics: SystemMetrics,
        processes: [ProcessInfoModel],
        samples: [SystemMetrics],
        findings: [BottleneckFinding],
        timeline: [TimelineIntelEvent],
        health: Double?
    ) -> ConfidenceFinding {
        let q = question.lowercased()

        if q.contains("hot") || q.contains("temperature") || q.contains("thermal") {
            if let temp = metrics.thermal.cpuTemperatureC {
                let top = processes.max(by: { $0.cpuPercent < $1.cpuPercent })
                return .init(
                    title: "Why is it hot?",
                    summary: String(format: "Measured CPU temperature is %.0f°C (thermal state: %@).", temp, metrics.thermal.thermalState.rawValue),
                    why: top.map { String(format: "%@ is using %.0f%% CPU, which correlates with the heat.", $0.name, $0.cpuPercent) }
                        ?? "No single process dominates; package heat still tracks overall CPU activity.",
                    confidence: top == nil ? 75 : 90,
                    category: "thermal",
                    evidence: [String(format: "%.1f°C", temp), "state \(metrics.thermal.thermalState.rawValue)"]
                )
            }
            return unavailable("CPU temperature sensor is not published on this Mac path.")
        }

        if q.contains("fan") {
            if let fan = metrics.thermal.fanSpeedsRPM.first {
                return .init(
                    title: "Why is the fan loud?",
                    summary: String(format: "%@ is spinning at %.0f RPM.", fan.name, fan.rpm),
                    why: String(format: "Fans rise with thermal load. CPU is %.0f%%; thermal state is %@.", metrics.cpu.totalUsage, metrics.thermal.thermalState.rawValue),
                    confidence: 88,
                    category: "cooling",
                    evidence: [String(format: "%.0f RPM", fan.rpm)]
                )
            }
            return unavailable("Fan RPM is not readable on this hardware (common on Apple Silicon without a privileged helper).")
        }

        if q.contains("battery") || q.contains("draining") {
            if !metrics.battery.isPresent {
                return unavailable("No battery is present on this machine.")
            }
            let pct = metrics.battery.chargePercent.map { String(format: "%.0f%%" , $0) } ?? "—"
            let top = processes.sorted { $0.cpuPercent > $1.cpuPercent }.prefix(3).map { "\($0.name) \(Int($0.cpuPercent))%" }.joined(separator: ", ")
            return .init(
                title: "Battery drain",
                summary: "Battery is at \(pct)\(metrics.battery.isCharging ? " (charging)" : "").",
                why: top.isEmpty ? "Process list did not show a clear power hog in CPU terms." : "Top CPU consumers right now: \(top).",
                confidence: 80,
                category: "battery",
                evidence: [pct, metrics.battery.isCharging ? "AC" : "Battery"]
            )
        }

        if q.contains("ssd") || q.contains("disk") || q.contains("storage") || q.contains("full") {
            if let root = metrics.storage.volumes.first(where: \.isRoot) {
                return .init(
                    title: "Storage",
                    summary: String(format: "Startup volume is %.0f%% used.", root.usedPercent),
                    why: "Free space figure comes from the mounted volume capacity APIs — not an estimate.",
                    confidence: 95,
                    category: "storage",
                    evidence: [String(format: "%.0f%% used", root.usedPercent)]
                )
            }
            return unavailable("No root volume metrics available.")
        }

        if q.contains("ram") || q.contains("memory") {
            let hog = processes.max(by: { $0.memoryBytes < $1.memoryBytes })
            return .init(
                title: "RAM usage",
                summary: String(format: "System memory is %.0f%% used (pressure %@).", metrics.memory.usagePercent, metrics.memory.pressure.rawValue),
                why: hog.map { "\($0.name) holds \(Formatters.bytes($0.memoryBytes))." } ?? "No dominant memory process found.",
                confidence: 92,
                category: "memory",
                evidence: [String(format: "%.0f%%", metrics.memory.usagePercent)]
            )
        }

        if q.contains("cpu") && (q.contains("most") || q.contains("which") || q.contains("who")) {
            if let top = processes.max(by: { $0.cpuPercent < $1.cpuPercent }) {
                return .init(
                    title: "Top CPU app",
                    summary: String(format: "%@ used the most CPU (%.0f%%) in the latest sample.", top.name, top.cpuPercent),
                    why: "Ranked from the live process table.",
                    confidence: 96,
                    category: "cpu",
                    evidence: [top.name]
                )
            }
        }

        if q.contains("yesterday") || q.contains("what happened") {
            let events = timeline.suffix(8)
            if events.isEmpty {
                return .init(
                    title: "Recent history",
                    summary: "Not enough explained timeline events are buffered yet.",
                    why: "Timeline Intelligence only records material changes while PulseMonitor is running.",
                    confidence: 55,
                    category: "timeline",
                    evidence: ["\(samples.count) metric samples in memory"]
                )
            }
            let lines = events.map { "• \($0.title) — \($0.reason)" }.joined(separator: "\n")
            return .init(
                title: "What happened",
                summary: "Recent explained events while monitoring was active:",
                why: lines,
                confidence: 70,
                category: "timeline",
                evidence: ["\(events.count) timeline events"]
            )
        }

        if q.contains("lag") || q.contains("minecraft") || q.contains("game") {
            let primary = findings.first
            return .init(
                title: "Performance lag",
                summary: primary?.summary ?? String(format: "CPU %.0f%% · Memory %.0f%% right now.", metrics.cpu.totalUsage, metrics.memory.usagePercent),
                why: primary?.detail.isEmpty == false ? primary!.detail : "Open Game Lab for session-level charts. FPS is not invented.",
                confidence: (primary?.confidence ?? 0.6) * 100,
                category: primary?.category.rawValue ?? "game",
                evidence: primary?.relatedProcesses ?? []
            )
        }

        if q.contains("health") || q.contains("how is my system") || q.contains("status") {
            return .init(
                title: "System status",
                summary: String(format: "Overall health score is %.0f/100.", health ?? 100),
                why: String(format: "CPU %.0f%% · Memory %.0f%% · Thermal %@.", metrics.cpu.totalUsage, metrics.memory.usagePercent, metrics.thermal.thermalState.rawValue),
                confidence: 90,
                category: "health",
                evidence: ["HealthScoreEngine average of available categories"]
            )
        }

        return .init(
            title: "Need a more specific question",
            summary: "Ask about heat, fans, battery, SSD, RAM, CPU leaders, lag, or recent events.",
            why: "Natural Language Engine only answers from measured samples, findings, and timeline events — never invents sensors.",
            confidence: 40,
            category: "nl",
            evidence: ["Offline rule matcher"]
        )
    }

    private func unavailable(_ reason: String) -> ConfidenceFinding {
        .init(
            title: "Unavailable",
            summary: reason,
            why: "PulseMonitor will not invent a value when the sensor path is missing.",
            confidence: 100,
            category: "honesty",
            evidence: [reason]
        )
    }
}

public struct PIEReportModule: Sendable {
    public init() {}

    public func dailyBriefing(
        samples: [SystemMetrics],
        processes: [ProcessInfoModel],
        health: Double?,
        suggestions: [ConfidenceFinding]
    ) -> DailyBriefing {
        let hour = Calendar.current.component(.hour, from: .now)
        let greeting: String
        switch hour {
        case 5..<12: greeting = "Good morning."
        case 12..<17: greeting = "Good afternoon."
        case 17..<22: greeting = "Good evening."
        default: greeting = "Hello."
        }

        let peakCPU = samples.map(\.cpu.totalUsage).max()
        let peakTemp = samples.compactMap(\.thermal.cpuTemperatureC).max()
        let topApp = processes.max(by: { $0.cpuPercent < $1.cpuPercent })?.name
        let activeHours: Double = {
            guard let first = samples.first?.timestamp, let last = samples.last?.timestamp, last > first else { return 0 }
            return last.timeIntervalSince(first) / 3600
        }()

        var highlights: [String] = []
        if let peakCPU {
            highlights.append(String(format: "Highest CPU in the buffered window: %.0f%%.", peakCPU))
        }
        if let peakTemp {
            highlights.append(String(format: "Highest measured temperature: %.0f°C.", peakTemp))
        } else {
            highlights.append("No CPU temperature samples were available in this window.")
        }
        if let health {
            highlights.append(String(format: "Current health score: %.0f/100.", health))
        }
        if samples.contains(where: \.thermal.isThrottling) {
            highlights.append("Thermal throttling was observed in the buffer.")
        } else {
            highlights.append("No thermal throttling flag observed in the buffer.")
        }
        if let topApp {
            highlights.append("Top application right now: \(topApp).")
        }
        if activeHours > 0 {
            highlights.append(String(format: "Monitoring window spans approximately %.1f hours.", activeHours))
        }

        let narrative = [
            greeting,
            "Here is your local system briefing from measured PulseMonitor data only.",
            highlights.prefix(4).joined(separator: " ")
        ].joined(separator: " ")

        return DailyBriefing(
            generatedAt: .now,
            greeting: greeting,
            narrative: narrative,
            highlights: highlights,
            recommendations: suggestions.prefix(4).map(\.summary),
            peakCPU: peakCPU,
            peakTemperatureC: peakTemp,
            topApp: topApp
        )
    }
}

public struct PIEKnowledgeModule: Sendable {
    public init() {}

    public func article(for topic: String, metrics: SystemMetrics) -> KnowledgeArticle {
        let key = topic.lowercased()
        switch key {
        case "cpu":
            return .init(
                topic: "CPU",
                definition: "The central processor executing threads scheduled by the OS.",
                healthyRange: "Sustained package temperatures often stay more comfortable below ~90°C; utilization depends on workload.",
                currentStatus: String(format: "%.0f%% utilization · thermal %@", metrics.cpu.totalUsage, metrics.thermal.thermalState.rawValue),
                importance: "CPU bottlenecks increase compile times, simulation cost, and UI hitching.",
                commonProblems: ["Background compilers", "Runaway browser helpers", "Thermal throttling under sustained load"],
                tips: ["Identify the top process before quitting apps", "Reduce parallel jobs if temperatures climb"]
            )
        case "gpu":
            let util = metrics.gpu.utilization.map { String(format: "%.0f%%", $0) } ?? "unavailable"
            return .init(
                topic: "GPU",
                definition: "Graphics processor used for Metal/UI composition and compute.",
                healthyRange: "High utilization is normal in games; idle should be low.",
                currentStatus: "Utilization \(util) · \(metrics.gpu.deviceName)",
                importance: "GPU limits frame delivery and some creative exports.",
                commonProblems: ["Unavailable public utilization counters on some Macs", "Compositor load misread as game GPU"],
                tips: ["Lower resolution/effects when GPU-limited", "PulseMonitor never invents FPS"]
            )
        case "memory", "ram":
            return .init(
                topic: "Memory",
                definition: "Physical RAM plus compressed memory and swap backing.",
                healthyRange: "Pressure should stay Normal for interactive work.",
                currentStatus: String(format: "%.0f%% used · pressure %@", metrics.memory.usagePercent, metrics.memory.pressure.displayName),
                importance: "Pressure causes jetsam, swap, and stutters.",
                commonProblems: ["Too many browser tabs", "Leaking long-lived apps"],
                tips: ["Sort Process Explorer by memory", "Reopen apps that grow without bound"]
            )
        case "battery":
            return .init(
                topic: "Battery",
                definition: "On notebooks, charge comes from AppleSmartBattery data.",
                healthyRange: "Health above ~80% is generally fine; cycle count rises with age.",
                currentStatus: metrics.battery.isPresent
                    ? String(format: "Charge %@ · health %@",
                             metrics.battery.chargePercent.map { String(format: "%.0f%%", $0) } ?? "—",
                             metrics.battery.healthPercent.map { String(format: "%.0f%%", $0) } ?? "—")
                    : "No battery present",
                importance: "Health and temperature affect runtime and longevity.",
                commonProblems: ["High CPU while untethered", "Warm charging"],
                tips: ["Find CPU hogs on battery", "Avoid heavy loads at 100% charge when hot"]
            )
        case "storage", "ssd":
            let root = metrics.storage.volumes.first(where: \.isRoot)
            return .init(
                topic: "Storage",
                definition: "Local volumes reporting capacity and recent I/O throughput.",
                healthyRange: "Keep meaningful free space on the startup volume for APFS and swap.",
                currentStatus: root.map { String(format: "Root %.0f%% used", $0.usedPercent) } ?? "No root volume",
                importance: "Low free space slows writes and increases wear from churn.",
                commonProblems: ["Full startup disk", "Indexing storms"],
                tips: ["Empty Trash", "Move large media off-internal"]
            )
        default:
            return .init(
                topic: topic,
                definition: "Sensor topic encyclopedia entry.",
                healthyRange: "Depends on workload and hardware.",
                currentStatus: "Select CPU, GPU, Memory, Battery, or Storage for a grounded article.",
                importance: "Understanding sensors prevents misreading normal load as failure.",
                commonProblems: ["Assuming unavailable sensors are zero"],
                tips: ["Prefer measured values and explicit unavailable states"]
            )
        }
    }
}

public enum VoiceIntentRouter: Sendable {
    public static func parse(_ utterance: String) -> VoiceCommandResult {
        let q = utterance.lowercased()
        if q.contains("benchmark") {
            return .init(intent: .runBenchmark, spokenReply: "Opening benchmarks when available.", confidence: 85, navigationHint: "benchmarks")
        }
        if q.contains("game") {
            return .init(intent: .openGaming, spokenReply: "Opening the gaming dashboard.", confidence: 80, navigationHint: "gamesLab")
        }
        if q.contains("report") || q.contains("briefing") {
            return .init(intent: .dailyReport, spokenReply: "Generating today's local briefing.", confidence: 82, navigationHint: "copilot")
        }
        if q.contains("fan") {
            return .init(intent: .whyFanLoud, spokenReply: "Checking measured fan RPM and thermal state.", confidence: 78, navigationHint: "copilot")
        }
        if q.contains("how is") || q.contains("status") {
            return .init(intent: .systemStatus, spokenReply: "Summarizing measured system status.", confidence: 88, navigationHint: "copilot")
        }
        return .init(intent: .unknown, spokenReply: "Try asking about system status, fans, benchmarks, or today's report.", confidence: 35, navigationHint: nil)
    }
}

import Foundation

// MARK: - Insight Module

public struct PIEInsightModule: Sendable {
    public init() {}

    public func liveInsights(
        metrics: SystemMetrics,
        processes: [ProcessInfoModel],
        findings: [BottleneckFinding],
        games: [ProcessInfoModel]
    ) -> [ConfidenceFinding] {
        var out: [ConfidenceFinding] = []

        if let top = processes.max(by: { $0.cpuPercent < $1.cpuPercent }), top.cpuPercent >= 20 {
            let conf = min(98, 55 + top.cpuPercent * 0.4)
            out.append(.init(
                title: "CPU explanation",
                summary: String(format: "CPU usage is high because %@ is using %.0f%%.", top.name, top.cpuPercent),
                why: String(
                    format: "%@ leads the process table at %.0f%% CPU while system total is %.0f%%.",
                    top.name, top.cpuPercent, metrics.cpu.totalUsage
                ),
                confidence: conf,
                category: "cpu",
                evidence: [
                    String(format: "Top process CPU: %.1f%% (%@)", top.cpuPercent, top.name),
                    String(format: "System CPU: %.1f%%", metrics.cpu.totalUsage)
                ],
                recommendations: ["Inspect \(top.name) in Process Explorer"]
            ))
        }

        if let hog = processes.max(by: { $0.memoryBytes < $1.memoryBytes }),
           hog.memoryBytes >= 1_500_000_000 {
            out.append(.init(
                title: "Memory explanation",
                summary: "\(hog.name) currently occupies \(Formatters.bytes(hog.memoryBytes)) of RAM.",
                why: String(
                    format: "Working set of %@ is %.0f%% of physical memory pressure context (system memory %.0f%% used).",
                    hog.name,
                    Double(hog.memoryBytes) / max(Double(metrics.memory.totalBytes), 1) * 100,
                    metrics.memory.usagePercent
                ),
                confidence: 92,
                category: "memory",
                evidence: [
                    "\(hog.name): \(Formatters.bytes(hog.memoryBytes))",
                    String(format: "System memory: %.0f%%", metrics.memory.usagePercent)
                ],
                recommendations: ["Close unused windows/tabs if this process is a browser"]
            ))
        }

        if let ws = processes.first(where: { $0.name == "WindowServer" }), ws.cpuPercent >= 25 {
            out.append(.init(
                title: "WindowServer load",
                summary: String(
                    format: "WindowServer is consuming CPU (%.0f%%), often from compositing, transparency, or display changes.",
                    ws.cpuPercent
                ),
                why: "WindowServer GPU time is not published to this app; only its process CPU is measured.",
                confidence: 80,
                category: "display",
                evidence: [String(format: "WindowServer CPU: %.1f%%", ws.cpuPercent)],
                recommendations: ["Reduce transparency", "Check Display Lab"]
            ))
        }

        if metrics.storage.readBytesPerSec + metrics.storage.writeBytesPerSec > 25_000_000 {
            let mds = processes.first { $0.name.localizedCaseInsensitiveContains("mds") || $0.name == "mds_stores" }
            let why = mds.map {
                String(format: "Background indexing (%@ at %.0f%% CPU) aligns with elevated disk throughput.", $0.name, $0.cpuPercent)
            } ?? "Elevated disk bytes/sec were measured; no indexer process stood out in the top list."
            out.append(.init(
                title: "Storage activity",
                summary: "Recent SSD/disk activity is elevated.",
                why: why,
                confidence: mds == nil ? 70 : 88,
                category: "storage",
                evidence: [
                    String(format: "Read: %@", Formatters.bytesPerSecond(metrics.storage.readBytesPerSec)),
                    String(format: "Write: %@", Formatters.bytesPerSecond(metrics.storage.writeBytesPerSec))
                ]
            ))
        }

        if let limited = classifyWorkloadLimit(metrics: metrics, games: games) {
            out.append(limited)
        }

        for finding in findings.prefix(4) {
            out.append(.init(
                title: finding.title,
                summary: finding.summary,
                why: finding.detail.isEmpty ? finding.summary : finding.detail,
                confidence: finding.confidence * 100,
                category: finding.category.rawValue,
                evidence: finding.relatedProcesses.map { "Related: \($0)" },
                recommendations: finding.recommendations
            ))
        }

        return dedupe(out).sorted { $0.confidence > $1.confidence }
    }

    public func primaryBottleneck(from insights: [ConfidenceFinding], findings: [BottleneckFinding]) -> ConfidenceFinding? {
        if let f = findings.first {
            return .init(
                title: "\(f.category.rawValue.uppercased()) bottleneck",
                summary: f.summary,
                why: f.detail.isEmpty ? f.summary : f.detail,
                confidence: f.confidence * 100,
                category: f.category.rawValue,
                evidence: f.relatedProcesses,
                recommendations: f.recommendations
            )
        }
        return insights.first { ["cpu", "gpu", "memory", "storage", "thermal", "network", "battery"].contains($0.category) }
    }

    private func classifyWorkloadLimit(metrics: SystemMetrics, games: [ProcessInfoModel]) -> ConfidenceFinding? {
        let label = games.first?.name ?? "This workload"
        if metrics.cpu.totalUsage > 85, let gpu = metrics.gpu.utilization, gpu < 45 {
            return .init(
                title: "CPU-limited workload",
                summary: "\(label) is CPU-limited.",
                why: String(format: "CPU at %.0f%% while GPU utilization is only %.0f%%.", metrics.cpu.totalUsage, gpu),
                confidence: 94,
                category: "cpu",
                evidence: ["CPU saturated", "GPU headroom present"]
            )
        }
        if let gpu = metrics.gpu.utilization, gpu > 90, metrics.cpu.totalUsage < 70 {
            return .init(
                title: "GPU-limited workload",
                summary: "\(label) is GPU-limited.",
                why: String(format: "GPU at %.0f%% while CPU is %.0f%%.", gpu, metrics.cpu.totalUsage),
                confidence: 93,
                category: "gpu",
                evidence: ["GPU saturated", "CPU headroom present"]
            )
        }
        if metrics.memory.usagePercent > 90 || metrics.memory.pressure.rawValue == "critical" {
            return .init(
                title: "Memory-limited workload",
                summary: "\(label) is memory-limited.",
                why: String(format: "Memory use is %.0f%% with pressure %@.", metrics.memory.usagePercent, metrics.memory.pressure.rawValue),
                confidence: 90,
                category: "memory",
                evidence: [String(format: "Memory %.0f%%", metrics.memory.usagePercent)]
            )
        }
        if let root = metrics.storage.volumes.first(where: \.isRoot), root.usedPercent > 92 {
            return .init(
                title: "Storage-limited system",
                summary: "This system is storage-limited.",
                why: String(format: "Startup volume is %.0f%% full.", root.usedPercent),
                confidence: 91,
                category: "storage",
                evidence: [String(format: "Root volume %.0f%%", root.usedPercent)]
            )
        }
        return nil
    }

    private func dedupe(_ items: [ConfidenceFinding]) -> [ConfidenceFinding] {
        var seen = Set<String>()
        return items.filter { seen.insert($0.title + $0.summary).inserted }
    }
}

// MARK: - Prediction Module

public struct PIEPredictionModule: Sendable {
    public init() {}

    public func predict(
        samples: [SystemMetrics],
        metrics: SystemMetrics,
        horizons: [PredictionHorizon] = PredictionHorizon.allCases
    ) -> [PIEPrediction] {
        guard samples.count >= 5 else { return [] }
        var out: [PIEPrediction] = []
        let cpuSeries = samples.map(\.cpu.totalUsage)
        let memSeries = samples.map(\.memory.usagePercent)
        let tempSeries = samples.compactMap(\.thermal.cpuTemperatureC)
        let interval = max(metricsCollectorInterval(samples), 1)

        for horizon in horizons {
            let steps = max(1, Int((Double(horizon.rawValue) * 60) / interval))

            if let nextCPU = extrapolate(cpuSeries, steps: steps) {
                if nextCPU >= 92 {
                    out.append(.init(
                        kind: .futureBottleneck,
                        horizon: horizon,
                        summary: String(format: "CPU may stay saturated (~%.0f%%) within %@ if the trend continues.", nextCPU, horizon.label),
                        confidence: confidenceForSeries(cpuSeries),
                        projectedValue: nextCPU,
                        unit: "%",
                        evidence: ["Linear trend over \(samples.count) samples"]
                    ))
                }
            }

            if let nextMem = extrapolate(memSeries, steps: steps), nextMem >= 93 {
                out.append(.init(
                    kind: .memoryExhaustion,
                    horizon: horizon,
                    summary: String(format: "Memory use may approach %.0f%% within %@.", min(100, nextMem), horizon.label),
                    confidence: confidenceForSeries(memSeries),
                    projectedValue: min(100, nextMem),
                    unit: "%",
                    evidence: ["Memory trend extrapolation"]
                ))
            }

            if tempSeries.count >= 5, let nextTemp = extrapolate(tempSeries, steps: steps) {
                out.append(.init(
                    kind: .temperature,
                    horizon: horizon,
                    summary: String(format: "Estimated CPU temperature ~%.0f°C in %@ (trend-based estimate).", nextTemp, horizon.label),
                    confidence: confidenceForSeries(tempSeries) * 0.85,
                    projectedValue: nextTemp,
                    unit: "°C",
                    evidence: ["Only uses measured CPU temperature samples"]
                ))
                if nextTemp >= 95 {
                    out.append(.init(
                        kind: .thermalThrottle,
                        horizon: horizon,
                        summary: String(format: "Thermal throttling risk within %@ if temperature trend continues toward %.0f°C.", horizon.label, nextTemp),
                        confidence: confidenceForSeries(tempSeries) * 0.8,
                        projectedValue: nextTemp,
                        unit: "°C",
                        evidence: ["Projection crosses typical throttle band"]
                    ))
                }
            }

            if metrics.battery.isPresent,
               let pct = metrics.battery.chargePercent,
               !metrics.battery.isCharging,
               let drain = batteryDrainPerMinute(samples),
               drain > 0.05 {
                let minutesLeft = pct / drain
                if minutesLeft <= Double(horizon.rawValue) + 5 {
                    out.append(.init(
                        kind: .batteryDepletion,
                        horizon: horizon,
                        summary: String(format: "At current drain (~%.2f%%/min), battery may reach low levels within ~%.0f minutes.", drain, minutesLeft),
                        confidence: min(90, 50 + Double(samples.count)),
                        projectedValue: max(0, minutesLeft),
                        unit: "min",
                        evidence: [String(format: "Observed drain %.2f%% per minute", drain)]
                    ))
                }
                out.append(.init(
                    kind: .batteryRuntime,
                    horizon: horizon,
                    summary: String(format: "Estimated remaining runtime ~%.0f minutes at the current measured drain rate.", minutesLeft),
                    confidence: min(88, 45 + Double(samples.count)),
                    projectedValue: minutesLeft,
                    unit: "min",
                    evidence: ["Derived from charge percent deltas in the sample window"]
                ))
            }

            if let root = metrics.storage.volumes.first(where: \.isRoot), root.usedPercent > 88 {
                out.append(.init(
                    kind: .storageSaturation,
                    horizon: horizon,
                    summary: String(format: "Startup volume is already %.0f%% full — saturation risk remains elevated over %@.", root.usedPercent, horizon.label),
                    confidence: 86,
                    projectedValue: root.usedPercent,
                    unit: "%",
                    evidence: ["Current free space measurement"]
                ))
            }

            let net = metrics.network.bytesInPerSec + metrics.network.bytesOutPerSec
            if net > 40_000_000 {
                out.append(.init(
                    kind: .networkCongestion,
                    horizon: horizon,
                    summary: "Network throughput is currently high; congestion symptoms may persist over \(horizon.label) if transfers continue.",
                    confidence: 72,
                    projectedValue: net,
                    unit: "B/s",
                    evidence: [Formatters.bytesPerSecond(net)]
                ))
            }

            if metrics.memory.swapUsedBytes > 500_000_000 {
                let swapGB = Double(metrics.memory.swapUsedBytes) / 1_000_000_000
                out.append(.init(
                    kind: .swapUsage,
                    horizon: horizon,
                    summary: String(format: "Swap is already ~%.1f GB; expect continued swap pressure over %@ while memory stays tight.", swapGB, horizon.label),
                    confidence: 84,
                    projectedValue: swapGB,
                    unit: "GB",
                    evidence: ["Measured swap used bytes"]
                ))
            }
        }

        return out.sorted { $0.confidence > $1.confidence }
    }

    public func predictedBottleneck(from predictions: [PIEPrediction]) -> PIEPrediction? {
        predictions.first { $0.kind == .futureBottleneck || $0.kind == .thermalThrottle || $0.kind == .memoryExhaustion }
    }

    private func extrapolate(_ values: [Double], steps: Int) -> Double? {
        guard let next = TrendCalculator.predictNext(of: values), let last = values.last else { return nil }
        let delta = next - last
        return last + delta * Double(max(steps, 1))
    }

    private func confidenceForSeries(_ values: [Double]) -> Double {
        min(92, 40 + Double(values.count) * 1.5)
    }

    private func metricsCollectorInterval(_ samples: [SystemMetrics]) -> Double {
        guard samples.count >= 2 else { return 2 }
        let dts = zip(samples.dropFirst(), samples).map { $0.0.timestamp.timeIntervalSince($0.1.timestamp) }.filter { $0 > 0 }
        guard !dts.isEmpty else { return 2 }
        return dts.reduce(0, +) / Double(dts.count)
    }

    private func batteryDrainPerMinute(_ samples: [SystemMetrics]) -> Double? {
        let points = samples.compactMap { m -> (Date, Double)? in
            guard m.battery.isPresent, let p = m.battery.chargePercent, !m.battery.isCharging else { return nil }
            return (m.timestamp, p)
        }
        guard let first = points.first, let last = points.last, last.0 > first.0 else { return nil }
        let minutes = last.0.timeIntervalSince(first.0) / 60
        guard minutes >= 1 else { return nil }
        let delta = first.1 - last.1
        guard delta > 0 else { return nil }
        return delta / minutes
    }
}

// MARK: - Pattern / Anomaly Module

public struct PIEPatternModule: Sendable {
    public init() {}

    public func anomalies(samples: [SystemMetrics], processes: [ProcessInfoModel], habits: PIEHabitProfile?) -> [ConfidenceFinding] {
        guard samples.count >= 8 else { return [] }
        var out: [ConfidenceFinding] = []
        let temps = samples.compactMap(\.thermal.cpuTemperatureC)
        if temps.count >= 5, let last = temps.last {
            let mean = temps.reduce(0, +) / Double(temps.count)
            let baseline = habits?.typicalCPUTempC ?? mean
            if last > baseline + 8 {
                out.append(.init(
                    title: "CPU temperature unusually high",
                    summary: String(format: "CPU temperature %.0f°C is well above the recent baseline (~%.0f°C).", last, baseline),
                    why: "Compared against the mean of the current sample window\(habits?.typicalCPUTempC == nil ? "" : " and learned typical temperature").",
                    confidence: 82,
                    category: "thermal",
                    evidence: [String(format: "Now %.1f°C vs baseline %.1f°C", last, baseline)],
                    isEstimate: habits?.typicalCPUTempC != nil
                ))
            }
        }

        let writes = samples.map(\.storage.writeBytesPerSec)
        if let last = writes.last, let mean = average(writes), last > mean * 4, last > 15_000_000 {
            out.append(.init(
                title: "SSD write activity abnormal",
                summary: "Disk write throughput is several times the recent average.",
                why: String(format: "Current write %@ vs window average %@.", Formatters.bytesPerSecond(last), Formatters.bytesPerSecond(mean)),
                confidence: 78,
                category: "storage",
                evidence: ["Write spike vs rolling mean"]
            ))
        }

        if let habitCPU = habits?.typicalCPUPercent,
           metricsLast(samples)?.cpu.totalUsage ?? 0 > habitCPU + 25 {
            out.append(.init(
                title: "CPU above learned habit",
                summary: String(format: "CPU is elevated versus your typical load (~%.0f%%).", habitCPU),
                why: "Learning Engine baseline from local history only.",
                confidence: 75,
                category: "cpu",
                evidence: [String(format: "Typical %.0f%%", habitCPU)],
                isEstimate: true
            ))
        }

        let mem = samples.map(\.memory.usagePercent)
        if mem.count >= 10, let first = mem.first, let last = mem.last, last - first > 12, last > 80 {
            out.append(.init(
                title: "Memory leak suspected",
                summary: "Memory use rose steadily across the recent window while remaining high.",
                why: String(format: "Memory moved from %.0f%% to %.0f%% over %d samples.", first, last, mem.count),
                confidence: 68,
                category: "memory",
                evidence: ["Monotonic-ish rise in sample window"],
                recommendations: ["Check the top RAM process for unbounded growth"],
                isEstimate: true
            ))
        }

        if let unexpected = unexpectedBackground(processes, habits: habits) {
            out.append(unexpected)
        }

        return out
    }

    private func unexpectedBackground(_ processes: [ProcessInfoModel], habits: PIEHabitProfile?) -> ConfidenceFinding? {
        guard let known = habits?.commonProcessNames, !known.isEmpty else { return nil }
        let hot = processes.filter { $0.cpuPercent >= 15 }.map(\.name)
        let strangers = hot.filter { name in !known.contains { $0.caseInsensitiveCompare(name) == .orderedSame } }
        guard let name = strangers.first else { return nil }
        return .init(
            title: "Unexpected background application",
            summary: "\(name) is busy but is not in your usual background set.",
            why: "Compared against locally learned common process names.",
            confidence: 64,
            category: "behaviour",
            evidence: ["Not in learned common set"],
            isEstimate: true
        )
    }

    private func metricsLast(_ samples: [SystemMetrics]) -> SystemMetrics? { samples.last }
    private func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}

// MARK: - Recommendation / Optimization

public struct PIERecommendationModule: Sendable {
    public init() {}

    public func recommend(
        metrics: SystemMetrics,
        processes: [ProcessInfoModel],
        insights: [ConfidenceFinding],
        workload: WorkloadDetection
    ) -> [ConfidenceFinding] {
        var out: [ConfidenceFinding] = []

        if let root = metrics.storage.volumes.first(where: \.isRoot), root.usedPercent > 85 {
            let free = root.freeBytes
            out.append(.init(
                title: "Free storage",
                summary: "Free space is getting low on the startup volume.",
                why: String(format: "Volume is %.0f%% full (%@ free).", root.usedPercent, Formatters.bytes(free)),
                confidence: 90,
                category: "storage",
                recommendations: ["Empty Trash", "Review large downloads", "Never auto-deleted by PulseMonitor"]
            ))
        }

        if let chrome = processes.first(where: { $0.name.localizedCaseInsensitiveContains("Chrome") || $0.name.localizedCaseInsensitiveContains("Chromium") }),
           chrome.memoryBytes > 2_000_000_000 {
            out.append(.init(
                title: "Close inactive browser tabs",
                summary: "\(chrome.name) is holding \(Formatters.bytes(chrome.memoryBytes)).",
                why: "Large browser working sets usually come from many tabs/renderers.",
                confidence: 80,
                category: "memory",
                recommendations: ["Close unused tabs", "Check Task Manager inside the browser"]
            ))
        }

        for tip in workload.advice.prefix(3) {
            out.append(.init(
                title: "Workload tip — \(workload.kind.displayName)",
                summary: tip,
                why: "Matched from detected workload \(workload.kind.displayName) (confidence \(Int(workload.confidence))%).",
                confidence: workload.confidence,
                category: "workload",
                recommendations: [tip]
            ))
        }

        out.append(contentsOf: insights.prefix(3).flatMap { insight in
            insight.recommendations.prefix(1).map {
                ConfidenceFinding(
                    title: "From insight: \(insight.title)",
                    summary: $0,
                    why: insight.why,
                    confidence: insight.confidence,
                    category: insight.category,
                    recommendations: [$0]
                )
            }
        })

        return out
    }
}

public struct PIEOptimizationModule: Sendable {
    public init() {}

    public func scorecard(
        health: Double,
        suggestions: [ConfidenceFinding],
        anomalies: [ConfidenceFinding]
    ) -> OptimizationScorecard {
        var score = health
        score -= Double(anomalies.filter { $0.confidence >= 75 }.count) * 4
        score -= Double(min(suggestions.count, 5)) * 1.5
        score = min(100, max(0, score))
        let summary: String
        if score >= 85 {
            summary = "Optimization headroom is good — only light optional improvements."
        } else if score >= 65 {
            summary = "Meaningful optimizations available; none are applied automatically."
        } else {
            summary = "Several evidence-backed improvements could raise comfort and longevity."
        }
        return .init(score: score, summary: summary, suggestions: suggestions)
    }
}

// MARK: - Timeline Intelligence

public struct PIETimelineModule: Sendable {
    public init() {}

    public func explain(
        previous: SystemMetrics?,
        current: SystemMetrics,
        processes: [ProcessInfoModel]
    ) -> [TimelineIntelEvent] {
        var events: [TimelineIntelEvent] = []
        let now = current.timestamp

        if current.cpu.totalUsage >= 90 {
            let top = processes.max(by: { $0.cpuPercent < $1.cpuPercent })
            events.append(.init(
                timestamp: now,
                title: String(format: "CPU reached %.0f%%.", current.cpu.totalUsage),
                reason: top.map { String(format: "%@ is leading at %.0f%% CPU.", $0.name, $0.cpuPercent) }
                    ?? "No single process exceeded the reporting threshold.",
                category: "cpu",
                confidence: top == nil ? 70 : 92
            ))
        }

        if let temp = current.thermal.cpuTemperatureC,
           let prev = previous?.thermal.cpuTemperatureC,
           temp - prev >= 3 {
            events.append(.init(
                timestamp: now,
                title: String(format: "Temperature increased to %.0f°C.", temp),
                reason: String(format: "Rose %.1f°C since the previous sample during measured load (CPU %.0f%%).", temp - prev, current.cpu.totalUsage),
                category: "thermal",
                confidence: 88
            ))
        }

        if let fan = current.thermal.fanSpeedsRPM.first,
           let prev = previous?.thermal.fanSpeedsRPM.first,
           fan.rpm > prev.rpm + 200 {
            events.append(.init(
                timestamp: now,
                title: String(format: "Fan speed increased to %.0f RPM.", fan.rpm),
                reason: "Automatic thermal response inferred from measured RPM rise (read-only).",
                category: "cooling",
                confidence: 85
            ))
        } else if current.thermal.fanSpeedsRPM.isEmpty,
                  current.thermal.thermalState == .serious || current.thermal.thermalState == .critical {
            events.append(.init(
                timestamp: now,
                title: "Thermal state elevated.",
                reason: "OS thermal state is \(current.thermal.thermalState.rawValue). Fan RPM is unavailable on this hardware path.",
                category: "thermal",
                confidence: 80
            ))
        }

        return events
    }
}

// MARK: - Workload Detector

public struct PIEWorkloadDetector: Sendable {
    public init() {}

    public func detect(processes: [ProcessInfoModel], games: [ProcessInfoModel], metrics: SystemMetrics) -> WorkloadDetection {
        if !games.isEmpty {
            return .init(
                kind: .gaming,
                confidence: 90,
                evidence: games.prefix(3).map(\.name),
                advice: ["Close overlays if frame time feels uneven", "Pause cloud sync during long sessions"]
            )
        }
        let names = processes.map { $0.name.lowercased() }
        if names.contains(where: { $0.contains("xcode") || $0.contains("swift") || $0.contains("code") || $0.contains("idea") }) {
            return .init(kind: .programming, confidence: 82, evidence: ["IDE / compiler processes present"], advice: ["Close unused simulators", "Limit parallel compile jobs if thermals rise"])
        }
        if names.contains(where: { $0.contains("final cut") || $0.contains("premiere") || $0.contains("davinci") || $0.contains("compressor") }) {
            return .init(kind: .videoEditing, confidence: 88, evidence: ["NLE process detected"], advice: ["Prefer proxy media when scrubbing", "Watch storage free space during export"])
        }
        if names.contains(where: { $0.contains("obs") || $0.contains("streamlabs") }) {
            return .init(kind: .streaming, confidence: 86, evidence: ["Streaming software detected"], advice: ["Cap encode resolution", "Avoid duplicate GPU capture pipelines"])
        }
        if names.contains(where: { $0.contains("qemu") || $0.contains("parallels") || $0.contains("vmware") || $0.contains("virtualbox") || $0.contains("utm") }) {
            return .init(kind: .virtualMachine, confidence: 87, evidence: ["VM hypervisor process detected"], advice: ["Right-size guest RAM", "Avoid nested GPU acceleration if unstable"])
        }
        if names.contains(where: { $0.contains("blender") || $0.contains("cinema 4d") || $0.contains("octane") }) {
            return .init(kind: .rendering, confidence: 85, evidence: ["Renderer detected"], advice: ["Monitor thermals during long frames"])
        }
        if names.contains(where: { $0.contains("chrome") || $0.contains("safari") || $0.contains("firefox") || $0.contains("edge") }) {
            return .init(kind: .browsing, confidence: 70, evidence: ["Browser dominant"], advice: ["Trim tabs if RAM pressure rises"])
        }
        if metrics.cpu.totalUsage < 20, metrics.memory.usagePercent < 60 {
            return .init(kind: .office, confidence: 55, evidence: ["Low interactive load"], advice: ["No urgent workload-specific action"])
        }
        return .init(kind: .unknown, confidence: 40, evidence: ["No strong signature"], advice: [])
    }
}

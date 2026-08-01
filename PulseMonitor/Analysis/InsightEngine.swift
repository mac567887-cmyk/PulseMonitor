import Foundation

/// A narrative observation drawn from recorded history rather than a live value.
public struct Insight: Sendable, Identifiable, Equatable {
    public enum Kind: String, Sendable {
        case thermal, memory, cpu, battery, storage, behaviour

        public var symbol: String {
            switch self {
            case .thermal: "thermometer.sun.fill"
            case .memory: "memorychip"
            case .cpu: "cpu"
            case .battery: "battery.75"
            case .storage: "internaldrive"
            case .behaviour: "chart.line.uptrend.xyaxis"
            }
        }
    }

    public let id: UUID
    public let kind: Kind
    public let headline: String
    public let body: String
    public let confidence: Double

    public init(id: UUID = UUID(), kind: Kind, headline: String, body: String, confidence: Double) {
        self.id = id
        self.kind = kind
        self.headline = headline
        self.body = body
        self.confidence = confidence
    }
}

/// Turns a window of recorded samples into plain-language observations.
///
/// Every insight is derived from counted evidence in the sample window — peaks,
/// durations, correlations between two series — and states what was measured so
/// the reader can judge it. Insights are withheld when the window is too short
/// to support a claim rather than being softened with hedging language.
public struct InsightEngine: Sendable {
    /// Samples below this count cannot support a trend claim.
    private let minimumSamples = 30

    public init() {}

    public func insights(
        from samples: [SystemMetrics],
        events: [SystemEvent],
        topProcessNames: [String]
    ) -> [Insight] {
        guard samples.count >= minimumSamples else { return [] }

        var results: [Insight] = []
        results.append(contentsOf: thermalInsights(samples: samples, events: events, processes: topProcessNames))
        results.append(contentsOf: memoryInsights(samples: samples))
        results.append(contentsOf: cpuInsights(samples: samples, processes: topProcessNames))
        results.append(contentsOf: batteryInsights(samples: samples))
        results.append(contentsOf: storageInsights(samples: samples))

        return results.sorted { $0.confidence > $1.confidence }
    }

    // MARK: - Thermal

    private func thermalInsights(
        samples: [SystemMetrics],
        events: [SystemEvent],
        processes: [String]
    ) -> [Insight] {
        let temperatures = samples.compactMap(\.thermal.cpuTemperatureC)
        guard temperatures.count >= minimumSamples else { return [] }

        var results: [Insight] = []
        let peak = temperatures.max() ?? 0
        let hotSamples = temperatures.filter { $0 > 90 }

        if !hotSamples.isEmpty, peak > 90 {
            // Count distinct excursions rather than samples, so a single long
            // heat soak is not reported as hundreds of separate events.
            var excursions = 0
            var inExcursion = false
            for temperature in temperatures {
                if temperature > 90, !inExcursion {
                    excursions += 1
                    inExcursion = true
                } else if temperature < 85 {
                    inExcursion = false
                }
            }

            let throttled = samples.filter(\.thermal.isThrottling).count
            let throttleShare = Double(throttled) / Double(samples.count) * 100

            var body = """
            Your Mac reached \(Int(peak))°C, crossing 90°C \(excursions) \
            \(excursions == 1 ? "time" : "times") during this window.
            """

            if throttled > 0 {
                body += " macOS was actively throttling for \(String(format: "%.0f", throttleShare))% of the period."

                // Quantify the cost by comparing clocks inside and outside throttling.
                let throttledClocks = samples.filter(\.thermal.isThrottling).compactMap(\.cpu.currentFrequencyMHz)
                let normalClocks = samples.filter { !$0.thermal.isThrottling }.compactMap(\.cpu.currentFrequencyMHz)
                if let hotAverage = average(throttledClocks),
                   let coolAverage = average(normalClocks),
                   coolAverage > 0, hotAverage < coolAverage {
                    let drop = (1 - hotAverage / coolAverage) * 100
                    body += " Clock speed fell by about \(String(format: "%.0f", drop))% while that was happening."
                }
            }

            if let culprit = processes.first {
                body += " \(culprit) was the largest CPU consumer across the same period."
            }

            results.append(.init(
                kind: .thermal,
                headline: throttled > 0 ? "Heat is costing you performance" : "Running hot but not throttled",
                body: body,
                confidence: throttled > 0 ? 0.9 : 0.7
            ))
        }

        let panics = events.filter { $0.category == .kernelPanic }
        if !panics.isEmpty {
            results.append(.init(
                kind: .thermal,
                headline: "\(panics.count) kernel \(panics.count == 1 ? "panic" : "panics") on record",
                body: """
                macOS recorded \(panics.count) kernel \(panics.count == 1 ? "panic" : "panics") in the last \
                thirty days. Panics are almost always a driver or hardware fault rather than an \
                application problem. The reports are in the Logs section.
                """,
                confidence: 0.95
            ))
        }

        return results
    }

    // MARK: - Memory

    private func memoryInsights(samples: [SystemMetrics]) -> [Insight] {
        var results: [Insight] = []

        let pressured = samples.filter { $0.memory.pressure != .normal }
        if Double(pressured.count) / Double(samples.count) > 0.15 {
            let share = Double(pressured.count) / Double(samples.count) * 100
            results.append(.init(
                kind: .memory,
                headline: "Memory pressure for \(String(format: "%.0f", share))% of this window",
                body: """
                Your Mac spent \(String(format: "%.0f", share))% of the period above normal memory pressure, \
                which means macOS was compressing pages to keep everything resident. This is the most \
                common cause of the beachball when switching between applications.
                """,
                confidence: 0.85
            ))
        }

        // A monotonic rise in swap across the window is the signature of a leak.
        let swap = samples.map { Double($0.memory.swapUsedBytes) }
        if let first = swap.first, let last = swap.last, last > first, last > 1_000_000_000 {
            let growth = last - first
            if growth > 500_000_000 {
                results.append(.init(
                    kind: .memory,
                    headline: "Swap grew by \(Formatters.bytes(UInt64(growth)))",
                    body: """
                    Swap usage rose from \(Formatters.bytes(UInt64(first))) to \(Formatters.bytes(UInt64(last))) \
                    without falling back. Steady one-way growth usually means an application is holding \
                    memory it is no longer using. Quitting and reopening the largest consumer will \
                    confirm whether that is the case.
                    """,
                    confidence: 0.75
                ))
            }
        }

        return results
    }

    // MARK: - CPU

    private func cpuInsights(samples: [SystemMetrics], processes: [String]) -> [Insight] {
        let usage = samples.map(\.cpu.totalUsage)
        guard let mean = average(usage) else { return [] }

        var results: [Insight] = []

        if mean > 45 {
            let busy = usage.filter { $0 > 80 }.count
            let share = Double(busy) / Double(usage.count) * 100
            var body = """
            Average CPU load was \(String(format: "%.0f", mean))% across this window, and it sat above 80% \
            for \(String(format: "%.0f", share))% of samples.
            """
            if let culprit = processes.first {
                body += " \(culprit) accounted for the largest share."
            }
            body += " Sustained load at this level is what makes fans audible and battery life short."

            results.append(.init(
                kind: .cpu,
                headline: "CPU averaged \(String(format: "%.0f", mean))%",
                body: body,
                confidence: 0.8
            ))
        }

        // Idle load is a distinct and more actionable finding than general load.
        let idlePeriods = samples.filter { $0.cpu.totalUsage > 15 && $0.gpu.utilization < 5 }
        if Double(idlePeriods.count) / Double(samples.count) > 0.6, mean < 40, let culprit = processes.first {
            results.append(.init(
                kind: .behaviour,
                headline: "Background work is constant",
                body: """
                The CPU never fully settled during this window even though the GPU stayed idle, which \
                points at background processing rather than anything on screen. \(culprit) was the \
                largest contributor. Indexing, sync and antivirus scans all produce this pattern.
                """,
                confidence: 0.65
            ))
        }

        return results
    }

    // MARK: - Battery

    private func batteryInsights(samples: [SystemMetrics]) -> [Insight] {
        guard let latest = samples.last, latest.battery.isPresent else { return [] }
        var results: [Insight] = []

        if let health = latest.battery.healthPercent, health < 80 {
            let cycles = latest.battery.cycleCount.map { " after \($0) cycles" } ?? ""
            results.append(.init(
                kind: .battery,
                headline: "Battery health is \(Int(health))%",
                body: """
                This battery holds \(Int(health))% of its original capacity\(cycles). Apple considers \
                a battery consumed below 80%, so runtime will be noticeably shorter than when the \
                machine was new and a replacement would restore it.
                """,
                confidence: 0.95
            ))
        }

        // Estimate drain from the actual charge trajectory while unplugged.
        let discharging = samples.filter { !$0.battery.isCharging && $0.battery.chargePercent != nil }
        if discharging.count > minimumSamples,
           let first = discharging.first, let last = discharging.last,
           let startPercent = first.battery.chargePercent,
           let endPercent = last.battery.chargePercent,
           startPercent > endPercent {
            let hours = last.timestamp.timeIntervalSince(first.timestamp) / 3600
            if hours > 0.08 {
                let ratePerHour = (startPercent - endPercent) / hours
                if ratePerHour > 20 {
                    let runtime = 100 / ratePerHour
                    results.append(.init(
                        kind: .battery,
                        headline: "Draining at \(String(format: "%.0f", ratePerHour))% per hour",
                        body: """
                        At the rate measured over the last \(String(format: "%.0f", hours * 60)) minutes, a full \
                        charge would last about \(String(format: "%.1f", runtime)) hours. That is faster than \
                        typical for light use and usually tracks back to sustained CPU load or a bright display.
                        """,
                        confidence: 0.7
                    ))
                }
            }
        }

        return results
    }

    // MARK: - Storage

    private func storageInsights(samples: [SystemMetrics]) -> [Insight] {
        guard let latest = samples.last,
              let root = latest.storage.volumes.first(where: \.isRoot) else { return [] }

        var results: [Insight] = []

        if root.usedPercent > 85 {
            results.append(.init(
                kind: .storage,
                headline: "\(Int(root.usedPercent))% of \(root.name) is in use",
                body: """
                \(Formatters.bytes(UInt64(root.freeBytes))) remains free. SSDs slow down as they fill \
                because the controller has fewer free blocks to write into, and macOS also needs \
                room for swap. Below about 10% free you will feel it.
                """,
                confidence: 0.9
            ))
        }

        let writes = samples.map(\.storage.writeBytesPerSec)
        if let meanWrite = average(writes), meanWrite > 20_000_000 {
            results.append(.init(
                kind: .storage,
                headline: "Sustained writes averaging \(Formatters.bytes(UInt64(meanWrite)))/s",
                body: """
                Something wrote continuously at \(Formatters.bytes(UInt64(meanWrite))) per second throughout \
                this window. Backups, cloud sync and Spotlight indexing are the usual causes. Constant \
                writing consumes SSD endurance and competes with everything else for I/O.
                """,
                confidence: 0.7
            ))
        }

        return results
    }

    // MARK: - Helpers

    private func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}

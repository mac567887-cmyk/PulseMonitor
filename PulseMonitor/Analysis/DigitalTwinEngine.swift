import Foundation

/// Live digital-twin projection built only from measured sensors.
/// Predictions are heuristic and labeled as estimates — never presented as ground truth.
public struct DigitalTwinState: Sendable, Codable, Equatable {
    public let timestamp: Date
    public let components: [TwinComponent]
    public let predictions: [TwinPrediction]
}

public struct TwinComponent: Sendable, Codable, Equatable, Identifiable {
    public var id: String { kind.rawValue }
    public let kind: Kind
    public let load: Double?
    public let temperatureC: Double?
    public let powerWatts: Double?
    public let health: Double?
    public let available: Bool
    public let unavailableReason: String?

    public enum Kind: String, CaseIterable, Sendable, Codable {
        case cpu, gpu, neuralEngine, memory, ssd, battery, fans, powerRails, wireless, thunderbolt, usb, sensors

        public var displayName: String {
            switch self {
            case .cpu: "CPU"
            case .gpu: "GPU"
            case .neuralEngine: "Neural Engine"
            case .memory: "RAM"
            case .ssd: "SSD"
            case .battery: "Battery"
            case .fans: "Fans"
            case .powerRails: "Power Rails"
            case .wireless: "Wireless"
            case .thunderbolt: "Thunderbolt"
            case .usb: "USB"
            case .sensors: "Sensors"
            }
        }
    }

    /// 0…1 heat for visualization from available signals.
    public var heat: Double {
        if let temperatureC {
            return min(1, max(0, (temperatureC - 40) / 60))
        }
        if let load { return min(1, max(0, load / 100)) }
        return 0
    }
}

public struct TwinPrediction: Sendable, Codable, Equatable, Identifiable {
    public var id: String { title }
    public let title: String
    public let detail: String
    public let confidence: Double
    public let isEstimate: Bool
}

public struct DigitalTwinEngine: Sendable {
    public init() {}

    public func project(
        metrics: SystemMetrics,
        previous: SystemMetrics?,
        usbCount: Int
    ) -> DigitalTwinState {
        let root = metrics.storage.volumes.first(where: \.isRoot)
        let fanLoad: Double? = {
            guard let fan = metrics.thermal.fanSpeedsRPM.first else { return nil }
            if let max = fan.maxRPM, max > 0 { return min(100, fan.rpm / max * 100) }
            return nil
        }()

        let components: [TwinComponent] = [
            .init(kind: .cpu, load: metrics.cpu.totalUsage, temperatureC: metrics.thermal.cpuTemperatureC,
                  powerWatts: metrics.cpu.packagePowerWatts ?? metrics.power.packageWatts,
                  health: nil, available: true, unavailableReason: nil),
            .init(kind: .gpu, load: metrics.gpu.utilization, temperatureC: metrics.gpu.temperatureC ?? metrics.thermal.gpuTemperatureC,
                  powerWatts: metrics.gpu.powerWatts, health: nil,
                  available: metrics.gpu.hasUtilizationCounters || metrics.gpu.temperatureC != nil,
                  unavailableReason: metrics.gpu.hasUtilizationCounters ? nil : "GPU counters not published"),
            .init(kind: .neuralEngine, load: nil, temperatureC: nil, powerWatts: nil, health: nil,
                  available: false, unavailableReason: "Neural Engine utilization is not exposed by a public API."),
            .init(kind: .memory, load: metrics.memory.usagePercent, temperatureC: nil, powerWatts: nil,
                  health: metrics.memory.pressure == .critical ? 40 : (metrics.memory.pressure == .warning ? 70 : 95),
                  available: true, unavailableReason: nil),
            .init(kind: .ssd, load: root?.usedPercent, temperatureC: metrics.thermal.ssdTemperatureC, powerWatts: nil,
                  health: metrics.storage.smartHealth == .failing ? 20 : (metrics.storage.smartHealth == .verified ? 95 : nil),
                  available: root != nil, unavailableReason: root == nil ? "No volume metrics" : nil),
            .init(kind: .battery, load: metrics.battery.chargePercent, temperatureC: metrics.battery.temperatureC ?? metrics.thermal.batteryTemperatureC,
                  powerWatts: metrics.battery.wattage, health: metrics.battery.healthPercent,
                  available: metrics.battery.isPresent, unavailableReason: metrics.battery.isPresent ? nil : "No battery"),
            .init(kind: .fans, load: fanLoad, temperatureC: nil, powerWatts: nil, health: nil,
                  available: !metrics.thermal.fanSpeedsRPM.isEmpty,
                  unavailableReason: metrics.thermal.fanSpeedsRPM.isEmpty ? "Fan RPM not published" : nil),
            .init(kind: .powerRails, load: nil, temperatureC: nil, powerWatts: metrics.power.totalSystemWatts,
                  health: nil, available: metrics.power.totalSystemWatts > 0,
                  unavailableReason: metrics.power.totalSystemWatts > 0 ? nil : "Package power unpublished"),
            .init(kind: .wireless, load: nil, temperatureC: nil, powerWatts: nil, health: nil,
                  available: true, unavailableReason: "Radio silicon load is not separately published; see Network module."),
            .init(kind: .thunderbolt, load: nil, temperatureC: nil, powerWatts: nil, health: nil,
                  available: false, unavailableReason: "Controller utilization is not available without private APIs."),
            .init(kind: .usb, load: Double(usbCount), temperatureC: nil, powerWatts: nil, health: nil,
                  available: true, unavailableReason: nil),
            .init(kind: .sensors, load: nil, temperatureC: metrics.thermal.cpuTemperatureC, powerWatts: nil, health: nil,
                  available: metrics.thermal.cpuTemperatureC != nil || !metrics.thermal.fanSpeedsRPM.isEmpty,
                  unavailableReason: nil)
        ]

        return DigitalTwinState(
            timestamp: .now,
            components: components,
            predictions: predictions(metrics: metrics, previous: previous)
        )
    }

    private func predictions(metrics: SystemMetrics, previous: SystemMetrics?) -> [TwinPrediction] {
        var list: [TwinPrediction] = []

        if let temp = metrics.thermal.cpuTemperatureC, let prev = previous?.thermal.cpuTemperatureC {
            let rise = temp - prev
            if rise > 2 {
                list.append(.init(
                    title: "Thermal climb",
                    detail: String(format: "CPU temperature rose %.1f°C since the last sample. Sustained climb often precedes frequency throttling.", rise),
                    confidence: 0.7,
                    isEstimate: true
                ))
            }
        }

        if metrics.thermal.isThrottling || metrics.thermal.thermalState.severity >= ThermalMetrics.ThermalState.serious.severity {
            list.append(.init(
                title: "Likely throttling",
                detail: "Thermal pressure is elevated. Expect reduced sustained CPU/GPU clocks until the package cools.",
                confidence: metrics.thermal.isThrottling ? 0.95 : 0.65,
                isEstimate: !metrics.thermal.isThrottling
            ))
        }

        if metrics.battery.isPresent, metrics.battery.isCharging == false {
            if let minutes = metrics.battery.timeRemainingMinutes, minutes > 0 {
                list.append(.init(
                    title: "Expected battery life",
                    detail: "System reports roughly \(minutes) minutes remaining at the current discharge rate.",
                    confidence: 0.8,
                    isEstimate: true
                ))
            } else if let watts = metrics.battery.wattage, watts < -1 {
                list.append(.init(
                    title: "Discharge rate",
                    detail: String(format: "Drawing about %.1f W on battery. Runtime depends on remaining capacity (not always published).", abs(watts)),
                    confidence: 0.55,
                    isEstimate: true
                ))
            }
        }

        if metrics.memory.pressure != .normal || metrics.memory.swapUsedBytes > 1_000_000_000 {
            list.append(.init(
                title: "Memory bottleneck risk",
                detail: "Memory pressure or active swap makes frame hitches and app quits more likely under additional load.",
                confidence: 0.75,
                isEstimate: true
            ))
        }

        if metrics.cpu.totalUsage > 90, let gpu = metrics.gpu.utilization, gpu < 45 {
            list.append(.init(
                title: "CPU-bound workload",
                detail: "CPU is saturated while GPU remains comparatively light — classic CPU bottleneck signature.",
                confidence: 0.85,
                isEstimate: false
            ))
        }

        if list.isEmpty {
            list.append(.init(
                title: "Stable projection",
                detail: "No strong thermal, memory or power warning signals in the latest samples.",
                confidence: 0.6,
                isEstimate: true
            ))
        }
        return list
    }
}

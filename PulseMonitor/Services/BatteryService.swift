import Foundation
import IOKit.ps

/// Reads battery and power-adapter state via IOKit Power Sources.
public actor BatteryService: MetricProviding {
    public typealias Metric = BatteryMetrics

    public init() {}

    public func sample() async -> BatteryMetrics {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else {
            return BatteryMetrics(
                isPresent: false, chargePercent: nil, isCharging: false, isFullyCharged: false,
                cycleCount: nil, designCapacitymAh: nil, currentCapacitymAh: nil, healthPercent: nil,
                voltagemV: nil, amperagemA: nil, wattage: nil, timeRemainingMinutes: nil,
                temperatureC: nil, powerSource: .acPower
            )
        }

        var battery: BatteryMetrics = .empty
        for source in list {
            guard let desc = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any] else {
                continue
            }
            let type = desc[kIOPSTypeKey] as? String
            guard type == kIOPSInternalBatteryType else { continue }

            let charge = desc[kIOPSCurrentCapacityKey] as? Double
            let isCharging = desc[kIOPSIsChargingKey] as? Bool ?? false
            let isCharged = desc[kIOPSIsChargedKey] as? Bool ?? false
            let cycle = desc["Cycle Count"] as? Int
            let design = desc[kIOPSDesignCapacityKey] as? Double
            let maxCap = desc[kIOPSMaxCapacityKey] as? Double
            let voltage = desc[kIOPSVoltageKey] as? Double
            let current = desc[kIOPSCurrentKey] as? Double
            let timeToEmpty = desc[kIOPSTimeToEmptyKey] as? Int
            let timeToFull = desc[kIOPSTimeToFullChargeKey] as? Int
            let temp = desc["Temperature"] as? Double
            let powerSourceState = desc[kIOPSPowerSourceStateKey] as? String

            let health: Double? = {
                guard let design, let maxCap, design > 0 else { return nil }
                return (maxCap / design) * 100.0
            }()

            let watts: Double? = {
                guard let voltage, let current else { return nil }
                return (voltage / 1000.0) * (current / 1000.0)
            }()

            let sourceKind: BatteryMetrics.PowerSource = {
                if powerSourceState == kIOPSACPowerValue { return .acPower }
                if powerSourceState == kIOPSBatteryPowerValue { return .battery }
                return .unknown
            }()

            let remaining: Int? = {
                if isCharging { return timeToFull == -1 ? nil : timeToFull }
                return timeToEmpty == -1 ? nil : timeToEmpty
            }()

            battery = BatteryMetrics(
                isPresent: true,
                chargePercent: charge,
                isCharging: isCharging,
                isFullyCharged: isCharged,
                cycleCount: cycle,
                designCapacitymAh: design,
                currentCapacitymAh: maxCap,
                healthPercent: health,
                voltagemV: voltage,
                amperagemA: current,
                wattage: watts,
                timeRemainingMinutes: remaining,
                temperatureC: temp.map { $0 > 200 ? $0 / 10.0 : $0 },
                powerSource: sourceKind
            )
        }

        if !battery.isPresent {
            // Desktop Macs without batteries
            return BatteryMetrics(
                isPresent: false, chargePercent: nil, isCharging: false, isFullyCharged: false,
                cycleCount: nil, designCapacitymAh: nil, currentCapacitymAh: nil, healthPercent: nil,
                voltagemV: nil, amperagemA: nil, wattage: nil, timeRemainingMinutes: nil,
                temperatureC: nil, powerSource: .acPower
            )
        }
        return battery
    }
}

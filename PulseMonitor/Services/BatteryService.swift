import Foundation
import IOKit
import IOKit.ps

/// Reads battery and power-adapter state via IOKit Power Sources, topped up with
/// the `AppleSmartBattery` registry entry.
///
/// The Power Sources description alone cannot report health or wear: it carries
/// neither the design capacity nor the cycle count on current macOS versions, so
/// anything derived from it would be a guess. The battery's IOService node does
/// publish those, and reading the registry needs no entitlement.
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

        let smart = Self.smartBatteryProperties()
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
            let timeToEmpty = desc[kIOPSTimeToEmptyKey] as? Int
            let timeToFull = desc[kIOPSTimeToFullChargeKey] as? Int
            let powerSourceState = desc[kIOPSPowerSourceStateKey] as? String

            let cycle = smart["CycleCount"] as? Int
            let design = (smart["DesignCapacity"] as? Double).flatMap { $0 > 0 ? $0 : nil }
            // AppleRawMaxCapacity is the true full-charge capacity in mAh.
            // MaxCapacity was redefined as a percentage on newer models, so it is
            // only trusted as a fallback when it is clearly not a percentage.
            let maxCap: Double? = {
                if let raw = smart["AppleRawMaxCapacity"] as? Double, raw > 0 { return raw }
                if let value = smart["MaxCapacity"] as? Double, value > 100 { return value }
                return nil
            }()
            let voltage = smart["Voltage"] as? Double ?? desc[kIOPSVoltageKey] as? Double
            let current = smart["Amperage"] as? Double ?? desc[kIOPSCurrentKey] as? Double
            // Reported in hundredths of a degree Celsius.
            let temp = (smart["Temperature"] as? Double).map { $0 / 100.0 }

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
                temperatureC: temp,
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

    /// Snapshot of the battery IOService properties. Empty on desktops and on any
    /// model that does not publish the node.
    private static func smartBatteryProperties() -> [String: Any] {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSmartBattery")
        )
        guard service != IO_OBJECT_NULL else { return [:] }
        defer { IOObjectRelease(service) }

        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let properties = unmanaged?.takeRetainedValue() as? [String: Any] else {
            return [:]
        }
        return properties
    }
}

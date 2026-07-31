import Foundation
import IOKit
import IOKit.ps

/// Monitors OS thermal state and attempts IOKit temperature reads when available.
public actor ThermalService: MetricProviding {
    public typealias Metric = ThermalMetrics

    public init() {}

    public func sample() async -> ThermalMetrics {
        let state = Self.mapThermalState(ProcessInfo.processInfo.thermalState)
        let isThrottling = state == .serious || state == .critical
        let reason: String? = {
            switch state {
            case .serious: return "System thermal pressure is elevated; clocks may be reduced."
            case .critical: return "Critical thermal pressure; significant throttling is active."
            default: return nil
            }
        }()

        let temps = Self.readTemperatures()
        let fans = Self.readFans()

        return ThermalMetrics(
            cpuTemperatureC: temps.cpu,
            gpuTemperatureC: temps.gpu,
            batteryTemperatureC: temps.battery,
            ssdTemperatureC: temps.ssd,
            ambientEstimateC: temps.ambient,
            thermalState: state,
            fanSpeedsRPM: fans,
            isThrottling: isThrottling,
            throttleReason: reason
        )
    }

    private static func mapThermalState(_ state: ProcessInfo.ThermalState) -> ThermalMetrics.ThermalState {
        switch state {
        case .nominal: .nominal
        case .fair: .fair
        case .serious: .serious
        case .critical: .critical
        @unknown default: .nominal
        }
    }

    /// Battery temperature via IOKit power sources; SMC die temps require entitlements.
    private static func readTemperatures() -> (cpu: Double?, gpu: Double?, battery: Double?, ssd: Double?, ambient: Double?) {
        let batteryTemp = readBatteryTemperature()
        return (nil, nil, batteryTemp, nil, nil)
    }

    private static func readBatteryTemperature() -> Double? {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return nil
        }
        for source in sources {
            if let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
               let temp = description["Temperature"] as? Double {
                return temp > 200 ? temp / 10.0 : temp
            }
        }
        return nil
    }

    private static func readFans() -> [ThermalMetrics.FanReading] {
        []
    }
}

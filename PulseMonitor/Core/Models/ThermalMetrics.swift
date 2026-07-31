import Foundation

/// Thermal sensors, fan speeds, and OS thermal pressure state.
public struct ThermalMetrics: Sendable, Codable, Equatable {
    public let cpuTemperatureC: Double?
    public let gpuTemperatureC: Double?
    public let batteryTemperatureC: Double?
    public let ssdTemperatureC: Double?
    public let ambientEstimateC: Double?
    public let thermalState: ThermalState
    public let fanSpeedsRPM: [FanReading]
    public let isThrottling: Bool
    public let throttleReason: String?

    public enum ThermalState: String, Sendable, Codable, Equatable {
        case nominal
        case fair
        case serious
        case critical

        public var displayName: String {
            rawValue.capitalized
        }

        public var severity: Int {
            switch self {
            case .nominal: 0
            case .fair: 1
            case .serious: 2
            case .critical: 3
            }
        }
    }

    public struct FanReading: Sendable, Codable, Equatable, Identifiable {
        public var id: String { name }
        public let name: String
        public let rpm: Double
        public let maxRPM: Double?
    }

    public static let empty = ThermalMetrics(
        cpuTemperatureC: nil, gpuTemperatureC: nil, batteryTemperatureC: nil,
        ssdTemperatureC: nil, ambientEstimateC: nil, thermalState: .nominal,
        fanSpeedsRPM: [], isThrottling: false, throttleReason: nil
    )
}

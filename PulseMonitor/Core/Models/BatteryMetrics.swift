import Foundation

/// Battery charge, health, cycles, and power-draw characteristics.
public struct BatteryMetrics: Sendable, Codable, Equatable {
    public let isPresent: Bool
    public let chargePercent: Double?
    public let isCharging: Bool
    public let isFullyCharged: Bool
    public let cycleCount: Int?
    public let designCapacitymAh: Double?
    public let currentCapacitymAh: Double?
    public let healthPercent: Double?
    public let voltagemV: Double?
    public let amperagemA: Double?
    public let wattage: Double?
    public let timeRemainingMinutes: Int?
    public let temperatureC: Double?
    public let powerSource: PowerSource

    public enum PowerSource: String, Sendable, Codable, Equatable {
        case battery
        case acPower
        case ups
        case unknown
    }

    public static let empty = BatteryMetrics(
        isPresent: false, chargePercent: nil, isCharging: false, isFullyCharged: false,
        cycleCount: nil, designCapacitymAh: nil, currentCapacitymAh: nil, healthPercent: nil,
        voltagemV: nil, amperagemA: nil, wattage: nil, timeRemainingMinutes: nil,
        temperatureC: nil, powerSource: .unknown
    )
}

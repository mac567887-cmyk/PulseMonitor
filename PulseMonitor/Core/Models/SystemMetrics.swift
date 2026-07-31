import Foundation

/// Snapshot of system-wide performance metrics collected at a single point in time.
public struct SystemMetrics: Sendable, Codable, Equatable {
    public let timestamp: Date
    public let cpu: CPUMetrics
    public let gpu: GPUMetrics
    public let memory: MemoryMetrics
    public let thermal: ThermalMetrics
    public let storage: StorageMetrics
    public let network: NetworkMetrics
    public let battery: BatteryMetrics
    public let power: PowerMetrics
    public let uptime: TimeInterval

    public init(
        timestamp: Date = .now,
        cpu: CPUMetrics,
        gpu: GPUMetrics,
        memory: MemoryMetrics,
        thermal: ThermalMetrics,
        storage: StorageMetrics,
        network: NetworkMetrics,
        battery: BatteryMetrics,
        power: PowerMetrics,
        uptime: TimeInterval
    ) {
        self.timestamp = timestamp
        self.cpu = cpu
        self.gpu = gpu
        self.memory = memory
        self.thermal = thermal
        self.storage = storage
        self.network = network
        self.battery = battery
        self.power = power
        self.uptime = uptime
    }
}

/// Aggregated power draw estimates in watts.
public struct PowerMetrics: Sendable, Codable, Equatable {
    public let packageWatts: Double
    public let gpuWatts: Double
    public let totalSystemWatts: Double
    public let isEstimated: Bool

    public static let empty = PowerMetrics(packageWatts: 0, gpuWatts: 0, totalSystemWatts: 0, isEstimated: true)
}

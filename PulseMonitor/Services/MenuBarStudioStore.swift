import Foundation
import Observation

/// User-designed menu bar metric strip.
public struct MenuBarStudioConfiguration: Sendable, Codable, Equatable {
    public var items: [Item]
    public var showMiniGraph: Bool
    public var compact: Bool

    public struct Item: Sendable, Codable, Equatable, Identifiable {
        public var id: String { kind.rawValue }
        public var kind: Kind
        public var enabled: Bool

        public enum Kind: String, CaseIterable, Codable, Sendable, Identifiable {
            case cpu, gpu, memory, temperature, battery, disk, network, power, clock

            public var id: String { rawValue }
            public var displayName: String {
                switch self {
                case .cpu: "CPU"
                case .gpu: "GPU"
                case .memory: "RAM"
                case .temperature: "Temp"
                case .battery: "Battery"
                case .disk: "Disk"
                case .network: "Network"
                case .power: "Power"
                case .clock: "Clock"
                }
            }
        }
    }

    public static let `default` = MenuBarStudioConfiguration(
        items: MenuBarStudioConfiguration.Item.Kind.allCases.map { .init(kind: $0, enabled: [.cpu, .memory, .temperature].contains($0)) },
        showMiniGraph: false,
        compact: true
    )
}

@MainActor
@Observable
public final class MenuBarStudioStore {
    public var configuration: MenuBarStudioConfiguration {
        didSet { persist() }
    }

    private let defaults: UserDefaults
    private let key = "v3.menuBarStudio"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode(MenuBarStudioConfiguration.self, from: data) {
            configuration = decoded
        } else {
            configuration = .default
        }
    }

    public func label(metrics: SystemMetrics?) -> String {
        let enabled = configuration.items.filter(\.enabled)
        guard !enabled.isEmpty else { return "Pulse" }
        let parts: [String] = enabled.compactMap { item in
            switch item.kind {
            case .cpu: return String(format: "CPU %.0f%%", metrics?.cpu.totalUsage ?? 0)
            case .gpu:
                if let gpu = metrics?.gpu.utilization { return String(format: "GPU %.0f%%", gpu) }
                return configuration.compact ? nil : "GPU —"
            case .memory: return String(format: "RAM %.0f%%", metrics?.memory.usagePercent ?? 0)
            case .temperature:
                if let t = metrics?.thermal.cpuTemperatureC ?? metrics?.thermal.batteryTemperatureC {
                    return String(format: "%.0f°C", t)
                }
                return nil
            case .battery:
                if let c = metrics?.battery.chargePercent, metrics?.battery.isPresent == true {
                    return String(format: "BAT %.0f%%", c)
                }
                return nil
            case .disk:
                let bps = (metrics?.storage.readBytesPerSec ?? 0) + (metrics?.storage.writeBytesPerSec ?? 0)
                return "Disk \(Formatters.bytesPerSecond(bps))"
            case .network:
                return Formatters.bytesPerSecond(metrics?.network.bytesInPerSec ?? 0)
            case .power:
                if let w = metrics?.power.totalSystemWatts, w > 0 { return Formatters.watts(w) }
                return nil
            case .clock:
                return Date.now.formatted(date: .omitted, time: .shortened)
            }
        }
        return parts.joined(separator: configuration.compact ? " " : " · ")
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(configuration) {
            defaults.set(data, forKey: key)
        }
    }
}

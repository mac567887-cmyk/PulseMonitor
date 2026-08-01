import Foundation
import Observation
import SwiftUI

/// User-configurable application settings persisted via UserDefaults.
@MainActor
@Observable
public final class AppSettings {
    public var refreshIntervalSeconds: Double {
        didSet {
            guard oldValue != refreshIntervalSeconds else { return }
            defaults.set(refreshIntervalSeconds, forKey: Keys.refresh)
        }
    }
    public var graphDurationSeconds: Double {
        didSet {
            guard oldValue != graphDurationSeconds else { return }
            defaults.set(graphDurationSeconds, forKey: Keys.graphDuration)
        }
    }
    public var historyRetention: HistoryRetention {
        didSet {
            guard oldValue != historyRetention else { return }
            defaults.set(historyRetention.rawValue, forKey: Keys.retention)
        }
    }
    public var cpuAlertThreshold: Double {
        didSet {
            guard oldValue != cpuAlertThreshold else { return }
            defaults.set(cpuAlertThreshold, forKey: Keys.cpuAlert)
        }
    }
    public var temperatureAlertC: Double {
        didSet {
            guard oldValue != temperatureAlertC else { return }
            defaults.set(temperatureAlertC, forKey: Keys.tempAlert)
        }
    }
    public var memoryPressureAlerts: Bool {
        didSet {
            guard oldValue != memoryPressureAlerts else { return }
            defaults.set(memoryPressureAlerts, forKey: Keys.memAlerts)
        }
    }
    public var showMenuBarExtra: Bool {
        didSet {
            guard oldValue != showMenuBarExtra else { return }
            defaults.set(showMenuBarExtra, forKey: Keys.menuBar)
        }
    }
    public var menuBarMetric: MenuBarMetric {
        didSet {
            guard oldValue != menuBarMetric else { return }
            defaults.set(menuBarMetric.rawValue, forKey: Keys.menuBarMetric)
        }
    }
    public var appearance: AppAppearance {
        didSet {
            guard oldValue != appearance else { return }
            defaults.set(appearance.rawValue, forKey: Keys.appearance)
        }
    }
    public var notificationsEnabled: Bool {
        didSet {
            guard oldValue != notificationsEnabled else { return }
            defaults.set(notificationsEnabled, forKey: Keys.notifications)
        }
    }

    public enum MenuBarMetric: String, CaseIterable, Identifiable, Codable {
        case cpu, memory, temperature, network, battery
        public var id: String { rawValue }
        public var displayName: String { rawValue.capitalized }
    }

    public enum AppAppearance: String, CaseIterable, Identifiable, Codable {
        case system, light, dark
        public var id: String { rawValue }
        public var displayName: String { rawValue.capitalized }
        public var colorScheme: ColorScheme? {
            switch self {
            case .system: nil
            case .light: .light
            case .dark: .dark
            }
        }
    }

    private let defaults: UserDefaults

    private enum Keys {
        static let refresh = "refreshIntervalSeconds"
        static let graphDuration = "graphDurationSeconds"
        static let retention = "historyRetention"
        static let cpuAlert = "cpuAlertThreshold"
        static let tempAlert = "temperatureAlertC"
        static let memAlerts = "memoryPressureAlerts"
        static let menuBar = "showMenuBarExtra"
        static let menuBarMetric = "menuBarMetric"
        static let appearance = "appearance"
        static let notifications = "notificationsEnabled"
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.refreshIntervalSeconds = defaults.object(forKey: Keys.refresh) as? Double ?? 1.0
        self.graphDurationSeconds = defaults.object(forKey: Keys.graphDuration) as? Double ?? 60.0
        let retentionRaw = defaults.string(forKey: Keys.retention) ?? HistoryRetention.twentyFourHours.rawValue
        self.historyRetention = HistoryRetention(rawValue: retentionRaw) ?? .twentyFourHours
        self.cpuAlertThreshold = defaults.object(forKey: Keys.cpuAlert) as? Double ?? 90.0
        self.temperatureAlertC = defaults.object(forKey: Keys.tempAlert) as? Double ?? 95.0
        self.memoryPressureAlerts = defaults.object(forKey: Keys.memAlerts) as? Bool ?? true
        self.showMenuBarExtra = defaults.object(forKey: Keys.menuBar) as? Bool ?? true
        let metricRaw = defaults.string(forKey: Keys.menuBarMetric) ?? MenuBarMetric.cpu.rawValue
        self.menuBarMetric = MenuBarMetric(rawValue: metricRaw) ?? .cpu
        let appearanceRaw = defaults.string(forKey: Keys.appearance) ?? AppAppearance.system.rawValue
        self.appearance = AppAppearance(rawValue: appearanceRaw) ?? .system
        self.notificationsEnabled = defaults.object(forKey: Keys.notifications) as? Bool ?? true
    }
}

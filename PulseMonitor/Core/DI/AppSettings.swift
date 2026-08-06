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

    // MARK: - Version 2 settings

    public var theme: Theme {
        didSet {
            guard oldValue != theme else { return }
            defaults.set(theme.rawValue, forKey: Keys.theme)
        }
    }
    public var overlayEnabled: Bool {
        didSet {
            guard oldValue != overlayEnabled else { return }
            defaults.set(overlayEnabled, forKey: Keys.overlayEnabled)
        }
    }
    public var overlayOpacity: Double {
        didSet {
            guard oldValue != overlayOpacity else { return }
            defaults.set(overlayOpacity, forKey: Keys.overlayOpacity)
        }
    }
    public var overlayAlwaysOnTop: Bool {
        didSet {
            guard oldValue != overlayAlwaysOnTop else { return }
            defaults.set(overlayAlwaysOnTop, forKey: Keys.overlayOnTop)
        }
    }
    public var overlayGameMode: Bool {
        didSet {
            guard oldValue != overlayGameMode else { return }
            defaults.set(overlayGameMode, forKey: Keys.overlayGameMode)
        }
    }
    /// Stored as a hex string so the preference survives colour-space changes.
    public var overlayTintHex: String {
        didSet {
            guard oldValue != overlayTintHex else { return }
            defaults.set(overlayTintHex, forKey: Keys.overlayTint)
        }
    }
    public var overlayMetrics: Set<OverlayMetric> {
        didSet {
            guard oldValue != overlayMetrics else { return }
            defaults.set(overlayMetrics.map(\.rawValue), forKey: Keys.overlayMetrics)
        }
    }
    public var activeProfile: PowerProfile.Kind {
        didSet {
            guard oldValue != activeProfile else { return }
            defaults.set(activeProfile.rawValue, forKey: Keys.activeProfile)
        }
    }
    public var automationEnabled: Bool {
        didSet {
            guard oldValue != automationEnabled else { return }
            defaults.set(automationEnabled, forKey: Keys.automation)
        }
    }
    public var developerModeEnabled: Bool {
        didSet {
            guard oldValue != developerModeEnabled else { return }
            defaults.set(developerModeEnabled, forKey: Keys.developerMode)
        }
    }

    // MARK: - Version 5 Athena / PIE

    public var aiLearningEnabled: Bool {
        didSet {
            guard oldValue != aiLearningEnabled else { return }
            defaults.set(aiLearningEnabled, forKey: Keys.aiLearning)
        }
    }
    public var aiConfidenceThreshold: Double {
        didSet {
            guard oldValue != aiConfidenceThreshold else { return }
            defaults.set(aiConfidenceThreshold, forKey: Keys.aiConfidence)
        }
    }
    public var aiInsightDetail: AIInsightDetail {
        didSet {
            guard oldValue != aiInsightDetail else { return }
            defaults.set(aiInsightDetail.rawValue, forKey: Keys.aiInsightDetail)
        }
    }
    public var aiPredictionFrequency: AIPredictionFrequency {
        didSet {
            guard oldValue != aiPredictionFrequency else { return }
            defaults.set(aiPredictionFrequency.rawValue, forKey: Keys.aiPredictionFreq)
        }
    }
    public var aiNotificationStyle: AINotificationStyle {
        didSet {
            guard oldValue != aiNotificationStyle else { return }
            defaults.set(aiNotificationStyle.rawValue, forKey: Keys.aiNotifyStyle)
        }
    }
    public var aiDeveloperReasoning: Bool {
        didSet {
            guard oldValue != aiDeveloperReasoning else { return }
            defaults.set(aiDeveloperReasoning, forKey: Keys.aiDevReasoning)
        }
    }

    public enum AIInsightDetail: String, CaseIterable, Identifiable, Codable {
        case concise, standard, detailed
        public var id: String { rawValue }
        public var displayName: String { rawValue.capitalized }
    }

    public enum AIPredictionFrequency: String, CaseIterable, Identifiable, Codable {
        case low, normal, high
        public var id: String { rawValue }
        public var displayName: String { rawValue.capitalized }
    }

    public enum AINotificationStyle: String, CaseIterable, Identifiable, Codable {
        case quiet, smart, verbose
        public var id: String { rawValue }
        public var displayName: String { rawValue.capitalized }
    }

    /// Metrics that may appear in the floating overlay.
    public enum OverlayMetric: String, CaseIterable, Identifiable, Codable, Sendable {
        case cpu, gpu, memory, temperature, battery, network, disk

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .cpu: "CPU"
            case .gpu: "GPU"
            case .memory: "RAM"
            case .temperature: "Temp"
            case .battery: "Battery"
            case .network: "Network"
            case .disk: "Disk"
            }
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
        static let theme = "theme"
        static let overlayEnabled = "overlayEnabled"
        static let overlayOpacity = "overlayOpacity"
        static let overlayOnTop = "overlayAlwaysOnTop"
        static let overlayGameMode = "overlayGameMode"
        static let overlayTint = "overlayTintHex"
        static let overlayMetrics = "overlayMetrics"
        static let activeProfile = "activeProfile"
        static let automation = "automationEnabled"
        static let developerMode = "developerModeEnabled"
        static let aiLearning = "aiLearningEnabled"
        static let aiConfidence = "aiConfidenceThreshold"
        static let aiInsightDetail = "aiInsightDetail"
        static let aiPredictionFreq = "aiPredictionFrequency"
        static let aiNotifyStyle = "aiNotificationStyle"
        static let aiDevReasoning = "aiDeveloperReasoning"
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

        let themeRaw = defaults.string(forKey: Keys.theme) ?? Theme.apple.rawValue
        self.theme = Theme(rawValue: themeRaw) ?? .apple
        self.overlayEnabled = defaults.object(forKey: Keys.overlayEnabled) as? Bool ?? false
        self.overlayOpacity = defaults.object(forKey: Keys.overlayOpacity) as? Double ?? 0.85
        self.overlayAlwaysOnTop = defaults.object(forKey: Keys.overlayOnTop) as? Bool ?? true
        self.overlayGameMode = defaults.object(forKey: Keys.overlayGameMode) as? Bool ?? false
        self.overlayTintHex = defaults.string(forKey: Keys.overlayTint) ?? "#5AA9FF"
        if let stored = defaults.array(forKey: Keys.overlayMetrics) as? [String] {
            self.overlayMetrics = Set(stored.compactMap(OverlayMetric.init(rawValue:)))
        } else {
            self.overlayMetrics = [.cpu, .memory, .temperature]
        }
        let profileRaw = defaults.string(forKey: Keys.activeProfile) ?? PowerProfile.Kind.balanced.rawValue
        self.activeProfile = PowerProfile.Kind(rawValue: profileRaw) ?? .balanced
        self.automationEnabled = defaults.object(forKey: Keys.automation) as? Bool ?? false
        self.developerModeEnabled = defaults.object(forKey: Keys.developerMode) as? Bool ?? false
        self.aiLearningEnabled = defaults.object(forKey: Keys.aiLearning) as? Bool ?? true
        self.aiConfidenceThreshold = defaults.object(forKey: Keys.aiConfidence) as? Double ?? 55
        let insightRaw = defaults.string(forKey: Keys.aiInsightDetail) ?? AIInsightDetail.standard.rawValue
        self.aiInsightDetail = AIInsightDetail(rawValue: insightRaw) ?? .standard
        let predRaw = defaults.string(forKey: Keys.aiPredictionFreq) ?? AIPredictionFrequency.normal.rawValue
        self.aiPredictionFrequency = AIPredictionFrequency(rawValue: predRaw) ?? .normal
        let notifyRaw = defaults.string(forKey: Keys.aiNotifyStyle) ?? AINotificationStyle.smart.rawValue
        self.aiNotificationStyle = AINotificationStyle(rawValue: notifyRaw) ?? .smart
        self.aiDeveloperReasoning = defaults.object(forKey: Keys.aiDevReasoning) as? Bool ?? false
    }
}

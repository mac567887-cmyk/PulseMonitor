import Foundation
import AppKit

/// A user-defined IF/THEN rule.
public struct AutomationRule: Sendable, Identifiable, Codable, Equatable {
    public enum Trigger: String, Codable, Sendable, CaseIterable, Identifiable {
        case cpuAbove
        case memoryPressureHigh
        case temperatureAbove
        case batteryBelow
        case swapAbove
        case diskSpaceBelow
        case gameLaunched
        case thermalThrottling

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .cpuAbove: "CPU usage above"
            case .memoryPressureHigh: "Memory pressure is not normal"
            case .temperatureAbove: "CPU temperature above"
            case .batteryBelow: "Battery charge below"
            case .swapAbove: "Swap usage above"
            case .diskSpaceBelow: "Free disk space below"
            case .gameLaunched: "A game is running"
            case .thermalThrottling: "Thermal throttling begins"
            }
        }

        /// Rules whose trigger needs a numeric comparison value.
        public var needsThreshold: Bool {
            switch self {
            case .memoryPressureHigh, .gameLaunched, .thermalThrottling: false
            default: true
            }
        }

        public var unit: String {
            switch self {
            case .cpuAbove: "%"
            case .temperatureAbove: "°C"
            case .batteryBelow: "%"
            case .swapAbove: "GB"
            case .diskSpaceBelow: "GB"
            default: ""
            }
        }

        public var defaultThreshold: Double {
            switch self {
            case .cpuAbove: 90
            case .temperatureAbove: 95
            case .batteryBelow: 20
            case .swapAbove: 4
            case .diskSpaceBelow: 10
            default: 0
            }
        }
    }

    public enum Action: String, Codable, Sendable, CaseIterable, Identifiable {
        case notify
        case exportReport
        case applyProfile
        case enableOverlay
        case disableOverlay
        case logEvent

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .notify: "Send a notification"
            case .exportReport: "Export a diagnostic report"
            case .applyProfile: "Switch power profile"
            case .enableOverlay: "Show the performance overlay"
            case .disableOverlay: "Hide the performance overlay"
            case .logEvent: "Write an entry to the event log"
            }
        }

        public var needsProfile: Bool { self == .applyProfile }
    }

    public let id: UUID
    public var name: String
    public var isEnabled: Bool
    public var trigger: Trigger
    public var threshold: Double
    public var action: Action
    public var profile: PowerProfile.Kind
    /// Minimum gap between firings, so a hovering value cannot spam the user.
    public var cooldownSeconds: Double

    public init(
        id: UUID = UUID(),
        name: String,
        isEnabled: Bool = true,
        trigger: Trigger,
        threshold: Double? = nil,
        action: Action,
        profile: PowerProfile.Kind = .balanced,
        cooldownSeconds: Double = 300
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.trigger = trigger
        self.threshold = threshold ?? trigger.defaultThreshold
        self.action = action
        self.profile = profile
        self.cooldownSeconds = cooldownSeconds
    }

    public var summary: String {
        let condition = trigger.needsThreshold
            ? "\(trigger.displayName) \(Int(threshold))\(trigger.unit)"
            : trigger.displayName
        let outcome = action == .applyProfile
            ? "switch to the \(profile.displayName) profile"
            : action.displayName.lowercased()
        return "If \(condition.lowercased()), \(outcome)."
    }
}

/// Evaluates automation rules against each metrics sample.
///
/// Rules only fire when their cooldown has elapsed, and every firing is written
/// to the event log so the user can see exactly what the app did on their behalf.
@MainActor
@Observable
public final class AutomationEngine {
    public private(set) var rules: [AutomationRule]
    public private(set) var lastFired: [UUID: Date] = [:]

    private let storageURL: URL
    private let settings: AppSettings
    private let eventLog: EventLogService
    private let profiles: PowerProfileService
    private let alerts: AlertService

    public init(
        settings: AppSettings,
        eventLog: EventLogService,
        profiles: PowerProfileService,
        alerts: AlertService
    ) {
        self.settings = settings
        self.eventLog = eventLog
        self.profiles = profiles
        self.alerts = alerts

        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let directory = support.appendingPathComponent("PulseMonitor", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.storageURL = directory.appendingPathComponent("automation.json")

        if let data = try? Data(contentsOf: storageURL),
           let decoded = try? JSONDecoder().decode([AutomationRule].self, from: data) {
            self.rules = decoded
        } else {
            self.rules = Self.defaultRules
        }
    }

    /// Shipped disabled so the app never acts before the user opts in.
    private static var defaultRules: [AutomationRule] {
        [
            .init(name: "Notify on sustained CPU load", isEnabled: false, trigger: .cpuAbove, threshold: 90, action: .notify),
            .init(name: "Report when running hot", isEnabled: false, trigger: .temperatureAbove, threshold: 95, action: .exportReport),
            .init(name: "Conserve on low battery", isEnabled: false, trigger: .batteryBelow, threshold: 20, action: .applyProfile, profile: .batterySaver),
            .init(name: "Gaming profile when a game starts", isEnabled: false, trigger: .gameLaunched, action: .applyProfile, profile: .gaming)
        ]
    }

    // MARK: - Rule management

    public func add(_ rule: AutomationRule) {
        rules.append(rule)
        persist()
    }

    public func update(_ rule: AutomationRule) {
        guard let index = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        rules[index] = rule
        persist()
    }

    public func remove(_ rule: AutomationRule) {
        rules.removeAll { $0.id == rule.id }
        persist()
    }

    public func setEnabled(_ enabled: Bool, for rule: AutomationRule) {
        guard let index = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        rules[index].isEnabled = enabled
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(rules) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }

    // MARK: - Evaluation

    public func evaluate(metrics: SystemMetrics, processes: [ProcessInfoModel]) {
        guard settings.automationEnabled else { return }
        let now = Date()

        for rule in rules where rule.isEnabled {
            guard matches(rule: rule, metrics: metrics, processes: processes) else { continue }
            if let last = lastFired[rule.id], now.timeIntervalSince(last) < rule.cooldownSeconds {
                continue
            }
            lastFired[rule.id] = now
            fire(rule, metrics: metrics)
        }
    }

    private func matches(
        rule: AutomationRule,
        metrics: SystemMetrics,
        processes: [ProcessInfoModel]
    ) -> Bool {
        switch rule.trigger {
        case .cpuAbove:
            metrics.cpu.totalUsage > rule.threshold

        case .memoryPressureHigh:
            metrics.memory.pressure != .normal

        case .temperatureAbove:
            (metrics.thermal.cpuTemperatureC ?? 0) > rule.threshold

        case .batteryBelow:
            metrics.battery.isPresent
                && !metrics.battery.isCharging
                && (metrics.battery.chargePercent ?? 100) < rule.threshold

        case .swapAbove:
            Double(metrics.memory.swapUsedBytes) > rule.threshold * 1_073_741_824

        case .diskSpaceBelow:
            metrics.storage.volumes.contains { volume in
                volume.isRoot && Double(volume.freeBytes) < rule.threshold * 1_073_741_824
            }

        case .gameLaunched:
            processes.contains { $0.isGame && $0.cpuPercent > 5 }

        case .thermalThrottling:
            metrics.thermal.isThrottling
        }
    }

    private func fire(_ rule: AutomationRule, metrics: SystemMetrics) {
        eventLog.record(.init(
            category: .power,
            severity: .notice,
            title: "Automation: \(rule.name)",
            detail: rule.summary
        ))

        switch rule.action {
        case .notify:
            let name = rule.name
            let summary = rule.summary
            Task { [alerts] in
                await alerts.sendAutomationNotification(title: name, body: summary)
            }

        case .exportReport:
            NotificationCenter.default.post(name: .pulseMonitorAutomationExportRequested, object: nil)

        case .applyProfile:
            profiles.apply(rule.profile)

        case .enableOverlay:
            settings.overlayEnabled = true

        case .disableOverlay:
            settings.overlayEnabled = false

        case .logEvent:
            break // The event log entry above is the whole action.
        }
    }
}

extension Notification.Name {
    /// Posted when an automation rule asks for a report, so the UI layer can run
    /// the export where it has access to the file system panel.
    public static let pulseMonitorAutomationExportRequested = Notification.Name(
        "PulseMonitorAutomationExportRequested"
    )
}

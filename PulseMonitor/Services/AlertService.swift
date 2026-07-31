import Foundation
import UserNotifications

/// Local notification alerts for critical system conditions. No telemetry.
public actor AlertService {
    private let settings: AppSettings
    private var lastAlertAt: [String: Date] = [:]
    private let cooldown: TimeInterval = 120

    public init(settings: AppSettings) {
        self.settings = settings
        Task { await Self.requestPermission() }
    }

    public func evaluate(metrics: SystemMetrics, analysis: AnalysisReport) async {
        let enabled = await MainActor.run { settings.notificationsEnabled }
        guard enabled else { return }

        let cpuThreshold = await MainActor.run { settings.cpuAlertThreshold }
        let tempThreshold = await MainActor.run { settings.temperatureAlertC }
        let memAlerts = await MainActor.run { settings.memoryPressureAlerts }

        if metrics.cpu.totalUsage >= cpuThreshold {
            await notify(key: "cpu", title: "High CPU Usage", body: String(format: "CPU is at %.0f%%.", metrics.cpu.totalUsage))
        }
        if let temp = metrics.thermal.cpuTemperatureC ?? metrics.thermal.batteryTemperatureC, temp >= tempThreshold {
            await notify(key: "temp", title: "Critical Temperature", body: String(format: "Temperature reached %.0f°C.", temp))
        }
        if memAlerts && metrics.memory.pressure == .critical {
            await notify(key: "memory", title: "Memory Pressure Critical", body: "macOS is under critical memory pressure.")
        }
        if metrics.thermal.isThrottling {
            await notify(key: "thermal", title: "Thermal Throttling", body: metrics.thermal.throttleReason ?? "Performance is being limited by heat.")
        }
        if let root = metrics.storage.volumes.first(where: \.isRoot), root.usedPercent > 90 {
            await notify(key: "storage", title: "Low Disk Space", body: String(format: "Boot volume is %.0f%% full.", root.usedPercent))
        }
        if let finding = analysis.primaryBottleneck, finding.severity == .critical {
            await notify(key: "bottleneck-\(finding.category.rawValue)", title: finding.title, body: finding.summary)
        }
    }

    private func notify(key: String, title: String, body: String) async {
        let now = Date()
        if let last = lastAlertAt[key], now.timeIntervalSince(last) < cooldown { return }
        lastAlertAt[key] = now

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: "pulse-\(key)-\(UUID().uuidString)", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    private static func requestPermission() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }
}

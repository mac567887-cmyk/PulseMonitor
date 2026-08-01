import Foundation
import AppKit

/// A single recorded system event.
public struct SystemEvent: Sendable, Identifiable, Codable, Equatable {
    public enum Category: String, Codable, Sendable, CaseIterable, Identifiable {
        case thermal
        case power
        case sleepWake
        case application
        case battery
        case hardware
        case crash
        case kernelPanic

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .thermal: "Thermal"
            case .power: "Power"
            case .sleepWake: "Sleep & Wake"
            case .application: "Applications"
            case .battery: "Battery"
            case .hardware: "Hardware"
            case .crash: "Crashes"
            case .kernelPanic: "Kernel Panics"
            }
        }

        public var symbol: String {
            switch self {
            case .thermal: "thermometer.high"
            case .power: "bolt"
            case .sleepWake: "powersleep"
            case .application: "app.badge"
            case .battery: "battery.50"
            case .hardware: "cpu"
            case .crash: "exclamationmark.triangle"
            case .kernelPanic: "exclamationmark.octagon"
            }
        }
    }

    public enum Severity: String, Codable, Sendable {
        case info, notice, warning, critical
    }

    public let id: UUID
    public let date: Date
    public let category: Category
    public let severity: Severity
    public let title: String
    public let detail: String?

    public init(
        id: UUID = UUID(),
        date: Date = .now,
        category: Category,
        severity: Severity = .info,
        title: String,
        detail: String? = nil
    ) {
        self.id = id
        self.date = date
        self.category = category
        self.severity = severity
        self.title = title
        self.detail = detail
    }
}

/// Records notable system events for later review.
///
/// Sleep, wake, power-source and application lifecycle events come from
/// `NSWorkspace`'s notification centre. Crash reports and panics are read from
/// the DiagnosticReports directories that macOS already writes.
@MainActor
@Observable
public final class EventLogService {
    public private(set) var events: [SystemEvent] = []

    private let storageURL: URL
    /// Held in a nonisolated box so `deinit`, which cannot touch main-actor
    /// state, can still unregister them.
    private let observers = ObserverTokens()
    private var lastThermalState: ProcessInfo.ThermalState?
    private var lastBatteryPercent: Int?
    private let maximumEvents = 2_000

    public init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let directory = support.appendingPathComponent("PulseMonitor", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.storageURL = directory.appendingPathComponent("events.json")

        if let data = try? Data(contentsOf: storageURL),
           let decoded = try? JSONDecoder().decode([SystemEvent].self, from: data) {
            events = decoded
        }

        importDiagnosticReports()
        startObserving()
        record(.init(category: .application, title: "PulseMonitor started"))
    }

    deinit {
        observers.removeAll()
    }

    /// Thread-safe store for notification tokens.
    private final class ObserverTokens: @unchecked Sendable {
        private var workspaceTokens: [NSObjectProtocol] = []
        private var defaultTokens: [NSObjectProtocol] = []
        private let lock = NSLock()

        func addWorkspace(_ token: NSObjectProtocol) {
            lock.lock(); defer { lock.unlock() }
            workspaceTokens.append(token)
        }

        func addDefault(_ token: NSObjectProtocol) {
            lock.lock(); defer { lock.unlock() }
            defaultTokens.append(token)
        }

        func removeAll() {
            lock.lock(); defer { lock.unlock() }
            for token in workspaceTokens {
                NSWorkspace.shared.notificationCenter.removeObserver(token)
            }
            for token in defaultTokens {
                NotificationCenter.default.removeObserver(token)
            }
            workspaceTokens.removeAll()
            defaultTokens.removeAll()
        }
    }

    // MARK: - Recording

    public func record(_ event: SystemEvent) {
        events.append(event)
        if events.count > maximumEvents {
            events.removeFirst(events.count - maximumEvents)
        }
        persist()
    }

    public func events(in category: SystemEvent.Category?) -> [SystemEvent] {
        let filtered = category.map { wanted in events.filter { $0.category == wanted } } ?? events
        return filtered.sorted { $0.date > $1.date }
    }

    public func clear() {
        events.removeAll()
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(events) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }

    // MARK: - Live observation

    private func startObserving() {
        let center = NSWorkspace.shared.notificationCenter

        func observe(_ name: NSNotification.Name, handler: @escaping @MainActor (Notification) -> Void) {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { notification in
                // `queue: .main` guarantees delivery on the main thread, but
                // Notification is not Sendable so the hop must be spelled out.
                nonisolated(unsafe) let payload = notification
                MainActor.assumeIsolated { handler(payload) }
            }
            observers.addWorkspace(token)
        }

        observe(NSWorkspace.willSleepNotification) { [weak self] _ in
            self?.record(.init(category: .sleepWake, severity: .notice, title: "System going to sleep"))
        }
        observe(NSWorkspace.didWakeNotification) { [weak self] _ in
            self?.record(.init(category: .sleepWake, severity: .notice, title: "System woke from sleep"))
        }
        observe(NSWorkspace.screensDidSleepNotification) { [weak self] _ in
            self?.record(.init(category: .sleepWake, title: "Displays went to sleep"))
        }
        observe(NSWorkspace.screensDidWakeNotification) { [weak self] _ in
            self?.record(.init(category: .sleepWake, title: "Displays woke"))
        }
        observe(NSWorkspace.didLaunchApplicationNotification) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let name = app.localizedName else { return }
            self?.record(.init(
                category: .application,
                title: "\(name) launched",
                detail: app.bundleIdentifier
            ))
        }
        observe(NSWorkspace.didTerminateApplicationNotification) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let name = app.localizedName else { return }
            self?.record(.init(
                category: .application,
                title: "\(name) quit",
                detail: app.bundleIdentifier
            ))
        }
        observe(NSWorkspace.didMountNotification) { [weak self] notification in
            let path = (notification.userInfo?["NSDevicePath"] as? String) ?? "Unknown volume"
            self?.record(.init(category: .hardware, title: "Volume mounted", detail: path))
        }
        observe(NSWorkspace.didUnmountNotification) { [weak self] notification in
            let path = (notification.userInfo?["NSDevicePath"] as? String) ?? "Unknown volume"
            self?.record(.init(category: .hardware, title: "Volume unmounted", detail: path))
        }

        let thermalToken = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.recordThermalState() }
        }
        observers.addDefault(thermalToken)
        lastThermalState = ProcessInfo.processInfo.thermalState
    }

    private func recordThermalState() {
        let state = ProcessInfo.processInfo.thermalState
        guard state != lastThermalState else { return }
        lastThermalState = state

        let severity: SystemEvent.Severity = switch state {
        case .nominal: .info
        case .fair: .notice
        case .serious: .warning
        case .critical: .critical
        @unknown default: .info
        }

        record(.init(
            category: .thermal,
            severity: severity,
            title: "Thermal state changed to \(Self.describe(state))",
            detail: state == .serious || state == .critical
                ? "macOS is reducing performance to shed heat."
                : nil
        ))
    }

    private static func describe(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: "Nominal"
        case .fair: "Fair"
        case .serious: "Serious"
        case .critical: "Critical"
        @unknown default: "Unknown"
        }
    }

    /// Called by the metrics loop so battery transitions land in the log.
    public func noteBattery(percent: Int, isCharging: Bool) {
        guard let last = lastBatteryPercent else {
            lastBatteryPercent = percent
            return
        }
        // Only log at ten-point boundaries to keep the log readable.
        let lastBucket = last / 10
        let bucket = percent / 10
        guard bucket != lastBucket else { return }
        lastBatteryPercent = percent

        let severity: SystemEvent.Severity = percent <= 10 && !isCharging ? .warning : .info
        record(.init(
            category: .battery,
            severity: severity,
            title: "Battery at \(percent)%",
            detail: isCharging ? "Charging" : "On battery power"
        ))
    }

    // MARK: - Diagnostic reports

    /// Reads crash and panic reports macOS has already written to disk.
    ///
    /// Only reports newer than the most recent one we imported are added, so
    /// repeated launches do not duplicate entries.
    private func importDiagnosticReports() {
        let directories = [
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Logs/DiagnosticReports", isDirectory: true),
            URL(fileURLWithPath: "/Library/Logs/DiagnosticReports")
        ]

        let alreadyKnown = Set(events.compactMap { $0.detail })
        var imported: [SystemEvent] = []

        for directory in directories {
            guard let entries = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.contentModificationDateKey]
            ) else { continue }

            for url in entries {
                let name = url.lastPathComponent
                guard !alreadyKnown.contains(url.path) else { continue }

                let isPanic = name.contains("panic") || url.pathExtension == "panic"
                let isCrash = url.pathExtension == "ips" || url.pathExtension == "crash"
                guard isPanic || isCrash else { continue }

                let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                // Ignore anything older than thirty days so the first run is fast.
                guard date.timeIntervalSinceNow > -30 * 86_400 else { continue }

                let process = name.split(separator: "-").first.map(String.init) ?? name
                imported.append(.init(
                    date: date,
                    category: isPanic ? .kernelPanic : .crash,
                    severity: isPanic ? .critical : .warning,
                    title: isPanic ? "Kernel panic recorded" : "\(process) crashed",
                    detail: url.path
                ))
            }
        }

        guard !imported.isEmpty else { return }
        events.append(contentsOf: imported)
        events.sort { $0.date < $1.date }
        if events.count > maximumEvents {
            events.removeFirst(events.count - maximumEvents)
        }
        persist()
    }
}

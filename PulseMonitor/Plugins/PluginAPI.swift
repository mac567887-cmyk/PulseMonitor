import Foundation

/// Capabilities a PulseMonitor plugin may contribute.
public enum PluginCapability: String, CaseIterable, Sendable, Codable, Identifiable {
    case widget
    case hardwareModule
    case sensor
    case exporter
    case theme
    case automation

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .widget: "Widgets"
        case .hardwareModule: "Hardware Modules"
        case .sensor: "Sensors"
        case .exporter: "Exporters"
        case .theme: "Themes"
        case .automation: "Automation"
        }
    }
}

/// Metadata declared by every loadable plugin package.
public struct PluginManifest: Sendable, Codable, Equatable, Identifiable, Hashable {
    public var id: String
    public var name: String
    public var version: String
    public var author: String
    public var summary: String
    public var capabilities: [PluginCapability]
    public var minimumAppVersion: String

    public init(
        id: String,
        name: String,
        version: String,
        author: String,
        summary: String,
        capabilities: [PluginCapability],
        minimumAppVersion: String = "2.0.0"
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.author = author
        self.summary = summary
        self.capabilities = capabilities
        self.minimumAppVersion = minimumAppVersion
    }
}

/// Snapshot a plugin may publish for the dashboard or exporters.
public struct PluginSensorReading: Sendable, Codable, Equatable, Identifiable {
    public var id: String
    public var label: String
    public var value: String
    public var unit: String?
    public var severity: Severity

    public enum Severity: String, Sendable, Codable {
        case nominal, notice, warning, critical
    }

    public init(
        id: String,
        label: String,
        value: String,
        unit: String? = nil,
        severity: Severity = .nominal
    ) {
        self.id = id
        self.label = label
        self.value = value
        self.unit = unit
        self.severity = severity
    }
}

/// Runtime state of a discovered plugin package.
public struct PluginRecord: Sendable, Identifiable, Equatable {
    public var id: String { manifest.id }
    public var manifest: PluginManifest
    public var bundleURL: URL?
    public var isEnabled: Bool
    public var isLoaded: Bool
    public var loadError: String?

    public init(
        manifest: PluginManifest,
        bundleURL: URL? = nil,
        isEnabled: Bool = false,
        isLoaded: Bool = false,
        loadError: String? = nil
    ) {
        self.manifest = manifest
        self.bundleURL = bundleURL
        self.isEnabled = isEnabled
        self.isLoaded = isLoaded
        self.loadError = loadError
    }
}

/// Narrow host surface passed into activated plugins.
@MainActor
public final class PluginHostContext {
    public var latestCPUUsage: () -> Double
    public var latestMemoryUsage: () -> Double
    public var log: (String) -> Void

    public init(
        latestCPUUsage: @escaping () -> Double,
        latestMemoryUsage: @escaping () -> Double,
        log: @escaping (String) -> Void
    ) {
        self.latestCPUUsage = latestCPUUsage
        self.latestMemoryUsage = latestMemoryUsage
        self.log = log
    }
}

/// Contract for code plugins. Built-in plugins implement this directly;
/// third-party packages are catalogued from disk and activated when supported.
@MainActor
public protocol PulsePlugin: AnyObject {
    var manifest: PluginManifest { get }
    func activate(host: PluginHostContext) throws
    func deactivate()
    func sensorReadings() -> [PluginSensorReading]
}

import AppKit
import Foundation
import Observation

/// Discovers, loads and manages PulseMonitor plugin packages.
///
/// Packages live in
/// `~/Library/Application Support/PulseMonitor/Plugins/<id>.pulsemonitorplugin/`
/// and declare an `Info.plist` with the keys documented in the README.
///
/// The host never invents sensors or themes when a package fails to load —
/// failures stay visible in Settings so the user knows exactly what happened.
@MainActor
@Observable
public final class PluginHost {
    public private(set) var plugins: [PluginRecord] = []
    public private(set) var lastScanError: String?

    private var instances: [String: any PulsePlugin] = [:]
    private var enabledIDs: Set<String>
    private let builtins: [any PulsePlugin]
    private weak var collector: MetricsCollector?
    private let defaults: UserDefaults
    private let fileManager: FileManager

    private enum Keys {
        static let enabled = "pluginHost.enabledIDs"
    }

    public init(
        builtins: [any PulsePlugin]? = nil,
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) {
        let resolved = builtins ?? [UptimeSensorPlugin()]
        self.builtins = resolved
        self.defaults = defaults
        self.fileManager = fileManager
        if let stored = defaults.array(forKey: Keys.enabled) as? [String] {
            self.enabledIDs = Set(stored)
        } else {
            self.enabledIDs = Set(resolved.map { $0.manifest.id })
        }
    }

    public func bind(collector: MetricsCollector) {
        self.collector = collector
    }

    /// Application Support directory that holds third-party plugin packages.
    public var pluginsDirectory: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base
            .appendingPathComponent("PulseMonitor", isDirectory: true)
            .appendingPathComponent("Plugins", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Rescans disk packages and reconciles enabled state.
    public func scan() {
        lastScanError = nil
        var discovered: [PluginRecord] = []

        for plugin in builtins {
            let id = plugin.manifest.id
            discovered.append(PluginRecord(
                manifest: plugin.manifest,
                bundleURL: nil,
                isEnabled: enabledIDs.contains(id),
                isLoaded: instances[id] != nil
            ))
        }

        do {
            let urls = try fileManager.contentsOfDirectory(
                at: pluginsDirectory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            for url in urls where url.pathExtension == "pulsemonitorplugin" {
                do {
                    let manifest = try Self.readManifest(at: url)
                    discovered.append(PluginRecord(
                        manifest: manifest,
                        bundleURL: url,
                        isEnabled: enabledIDs.contains(manifest.id),
                        isLoaded: instances[manifest.id] != nil
                    ))
                } catch {
                    discovered.append(PluginRecord(
                        manifest: PluginManifest(
                            id: url.deletingPathExtension().lastPathComponent,
                            name: url.deletingPathExtension().lastPathComponent,
                            version: "?",
                            author: "Unknown",
                            summary: "Failed to read package.",
                            capabilities: []
                        ),
                        bundleURL: url,
                        isEnabled: false,
                        isLoaded: false,
                        loadError: error.localizedDescription
                    ))
                }
            }
        } catch {
            lastScanError = error.localizedDescription
        }

        plugins = discovered.sorted {
            $0.manifest.name.localizedCaseInsensitiveCompare($1.manifest.name) == .orderedAscending
        }
        reconcileLoadedInstances()
    }

    public func setEnabled(_ id: String, enabled: Bool) {
        if enabled {
            enabledIDs.insert(id)
        } else {
            enabledIDs.remove(id)
        }
        defaults.set(Array(enabledIDs), forKey: Keys.enabled)
        reconcileLoadedInstances()
        if let index = plugins.firstIndex(where: { $0.manifest.id == id }) {
            plugins[index].isEnabled = enabled
            plugins[index].isLoaded = instances[id] != nil
            if enabled && instances[id] == nil {
                plugins[index].loadError = plugins[index].loadError ?? "Failed to activate plugin."
            } else if instances[id] != nil {
                plugins[index].loadError = nil
            }
        }
    }

    public func openPluginsFolder() {
        NSWorkspace.shared.open(pluginsDirectory)
    }

    /// Aggregate sensor readings from every active plugin.
    public func sensorReadings() -> [PluginSensorReading] {
        instances.values.flatMap { $0.sensorReadings() }
    }

    // MARK: - Private

    private func reconcileLoadedInstances() {
        let host = makeHostContext()

        for id in Array(instances.keys) where !enabledIDs.contains(id) {
            instances[id]?.deactivate()
            instances.removeValue(forKey: id)
        }

        for record in plugins where record.isEnabled {
            let id = record.manifest.id
            guard instances[id] == nil else { continue }
            do {
                let instance = try instantiate(record)
                try instance.activate(host: host)
                instances[id] = instance
                if let index = plugins.firstIndex(where: { $0.manifest.id == id }) {
                    plugins[index].isLoaded = true
                    plugins[index].loadError = nil
                }
            } catch {
                if let index = plugins.firstIndex(where: { $0.manifest.id == id }) {
                    plugins[index].isLoaded = false
                    plugins[index].loadError = error.localizedDescription
                }
            }
        }
    }

    private func instantiate(_ record: PluginRecord) throws -> any PulsePlugin {
        if let builtin = builtins.first(where: { $0.manifest.id == record.manifest.id }) {
            return builtin
        }
        guard record.bundleURL != nil else {
            throw PluginError.missingBundle(record.manifest.id)
        }
        // Disk packages are catalogued and can be toggled. Native code loading is
        // reserved for signed companion builds; metadata packages activate as a
        // no-op stub so enabling them is honest rather than silently failing.
        return MetadataOnlyPlugin(manifest: record.manifest)
    }

    private func makeHostContext() -> PluginHostContext {
        PluginHostContext(
            latestCPUUsage: { [weak self] in
                guard let self else { return 0 }
                return self.collector?.latestMetrics?.cpu.totalUsage ?? 0
            },
            latestMemoryUsage: { [weak self] in
                guard let self else { return 0 }
                return self.collector?.latestMetrics?.memory.usagePercent ?? 0
            },
            log: { message in
                NSLog("[PulsePlugin] %@", message)
            }
        )
    }

    private static func readManifest(at url: URL) throws -> PluginManifest {
        let plistURL = url.appendingPathComponent("Info.plist")
        let data = try Data(contentsOf: plistURL)
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        guard let dict = plist as? [String: Any] else {
            throw PluginError.invalidManifest(url.lastPathComponent)
        }
        guard
            let id = dict["PMPluginIdentifier"] as? String,
            let name = dict["PMPluginName"] as? String
        else {
            throw PluginError.invalidManifest(url.lastPathComponent)
        }
        let capabilities = (dict["PMPluginCapabilities"] as? [String] ?? [])
            .compactMap(PluginCapability.init(rawValue:))
        return PluginManifest(
            id: id,
            name: name,
            version: dict["PMPluginVersion"] as? String ?? "1.0",
            author: dict["PMPluginAuthor"] as? String ?? "Unknown",
            summary: dict["PMPluginSummary"] as? String ?? "",
            capabilities: capabilities,
            minimumAppVersion: dict["PMMinimumAppVersion"] as? String ?? "2.0.0"
        )
    }
}

public enum PluginError: LocalizedError {
    case missingBundle(String)
    case invalidManifest(String)
    case codePluginUnavailable(String)

    public var errorDescription: String? {
        switch self {
        case .missingBundle(let id):
            "No bundle found for plugin \(id)."
        case .invalidManifest(let name):
            "\(name) is missing required Info.plist keys (PMPluginIdentifier, PMPluginName)."
        case .codePluginUnavailable(let name):
            "\(name) is a third-party package. This build activates built-in Swift plugins and catalogues disk packages; native code plugins require a signed companion loadable."
        }
    }
}

/// Placeholder for third-party packages that only ship Info.plist metadata.
@MainActor
final class MetadataOnlyPlugin: PulsePlugin {
    let manifest: PluginManifest
    init(manifest: PluginManifest) { self.manifest = manifest }
    func activate(host: PluginHostContext) throws {
        host.log("Metadata plugin \(manifest.id) registered")
    }
    func deactivate() {}
    func sensorReadings() -> [PluginSensorReading] { [] }
}

/// Built-in sensor that proves the plugin pipeline without any third-party code.
@MainActor
final class UptimeSensorPlugin: PulsePlugin {
    let manifest = PluginManifest(
        id: "com.pulsemonitor.plugin.uptime",
        name: "System Uptime",
        version: "1.0.0",
        author: "PulseMonitor",
        summary: "Exposes host uptime as a plugin sensor reading.",
        capabilities: [.sensor]
    )

    func activate(host: PluginHostContext) throws {
        host.log("Uptime sensor activated")
    }

    func deactivate() {}

    func sensorReadings() -> [PluginSensorReading] {
        let seconds = ProcessInfo.processInfo.systemUptime
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        return [
            PluginSensorReading(
                id: "uptime",
                label: "Uptime",
                value: "\(hours)h \(minutes)m",
                severity: .nominal
            )
        ]
    }
}

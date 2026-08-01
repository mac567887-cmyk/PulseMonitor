import Foundation
import AppKit

/// One installed application and everything we could learn about it on disk.
public struct InstalledApp: Sendable, Identifiable, Hashable {
    public var id: String { bundlePath }
    public let name: String
    public let bundlePath: String
    public let bundleIdentifier: String?
    public let version: String?
    public let buildNumber: String?
    public let developer: String?
    public let architecture: BinaryArchitecture
    public let sizeBytes: Int64?
    public let lastModified: Date?
    public let minimumSystemVersion: String?

    public var url: URL { URL(fileURLWithPath: bundlePath) }
}

/// Architectures a Mach-O executable can advertise.
public enum BinaryArchitecture: String, Sendable, Hashable {
    case appleSilicon = "Apple Silicon"
    case intel = "Intel"
    case universal = "Universal"
    case unknown = "Unknown"

    public var symbol: String {
        switch self {
        case .appleSilicon: "cpu.fill"
        case .intel: "cpu"
        case .universal: "square.stack.3d.up.fill"
        case .unknown: "questionmark.square.dashed"
        }
    }
}

/// Enumerates installed applications and performs the lifecycle actions macOS
/// permits from an unprivileged process.
///
/// Destructive operations route through `NSWorkspace.recycle`, which moves items
/// to the Trash rather than deleting them, and are never invoked automatically.
public actor AppManagerService {
    private var cache: [InstalledApp] = []
    private var lastScan: Date?

    public init() {}

    /// Scans the standard application directories. Results are cached for a
    /// minute because the scan touches every bundle's Info.plist.
    public func installedApps(forceRefresh: Bool = false) -> [InstalledApp] {
        if !forceRefresh, let lastScan, Date().timeIntervalSince(lastScan) < 60, !cache.isEmpty {
            return cache
        }

        let directories = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/Applications/Utilities"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Applications/Utilities"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        ]

        var seen = Set<String>()
        var apps: [InstalledApp] = []

        for directory in directories {
            guard let entries = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey, .totalFileAllocatedSizeKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for entry in entries where entry.pathExtension == "app" {
                guard seen.insert(entry.path).inserted else { continue }
                if let app = describe(bundleURL: entry) {
                    apps.append(app)
                }
            }
        }

        cache = apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        lastScan = Date()
        return cache
    }

    private func describe(bundleURL: URL) -> InstalledApp? {
        guard let bundle = Bundle(url: bundleURL) else { return nil }
        let info = bundle.infoDictionary ?? [:]

        let name = (info["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String)
            ?? bundleURL.deletingPathExtension().lastPathComponent

        let attributes = try? FileManager.default.attributesOfItem(atPath: bundleURL.path)

        return InstalledApp(
            name: name,
            bundlePath: bundleURL.path,
            bundleIdentifier: bundle.bundleIdentifier,
            version: info["CFBundleShortVersionString"] as? String,
            buildNumber: info["CFBundleVersion"] as? String,
            developer: Self.signingAuthority(for: bundleURL),
            architecture: Self.architecture(of: bundle.executableURL),
            sizeBytes: attributes?[.size] as? Int64,
            lastModified: attributes?[.modificationDate] as? Date,
            minimumSystemVersion: info["LSMinimumSystemVersion"] as? String
        )
    }

    // MARK: - Mach-O inspection

    /// Reads the Mach-O header to determine which architectures are present.
    ///
    /// Only the first sixteen bytes plus the fat arch table are read, so this
    /// stays cheap even across several hundred bundles.
    private static func architecture(of executable: URL?) -> BinaryArchitecture {
        guard let executable,
              let handle = try? FileHandle(forReadingFrom: executable) else { return .unknown }
        defer { try? handle.close() }

        guard let header = try? handle.read(upToCount: 8), header.count == 8 else { return .unknown }
        let magic = header.withUnsafeBytes { $0.load(as: UInt32.self) }

        let fatMagic: UInt32 = 0xcafebabe
        let fatCigam: UInt32 = 0xbebafeca
        let fatMagic64: UInt32 = 0xcafebabf
        let fatCigam64: UInt32 = 0xbfbafeca

        if magic == fatMagic || magic == fatCigam || magic == fatMagic64 || magic == fatCigam64 {
            return fatArchitecture(handle: handle, header: header, swapped: magic == fatCigam || magic == fatCigam64)
        }

        // Thin binary: the cputype immediately follows the magic.
        let cpuType = header.withUnsafeBytes { $0.load(fromByteOffset: 4, as: Int32.self) }
        return architecture(forCPUType: cpuType) ?? .unknown
    }

    private static func fatArchitecture(handle: FileHandle, header: Data, swapped: Bool) -> BinaryArchitecture {
        let rawCount = header.withUnsafeBytes { $0.load(fromByteOffset: 4, as: UInt32.self) }
        let count = swapped ? rawCount.byteSwapped : rawCount
        guard count > 0, count < 32 else { return .unknown }

        var found: Set<BinaryArchitecture> = []
        // Each fat_arch entry is 20 bytes and begins with the cputype.
        for index in 0..<Int(count) {
            try? handle.seek(toOffset: UInt64(8 + index * 20))
            guard let entry = try? handle.read(upToCount: 4), entry.count == 4 else { break }
            let raw = entry.withUnsafeBytes { $0.load(as: Int32.self) }
            let cpuType = swapped ? raw.byteSwapped : raw
            if let architecture = architecture(forCPUType: cpuType) {
                found.insert(architecture)
            }
        }

        if found.count > 1 { return .universal }
        return found.first ?? .unknown
    }

    private static func architecture(forCPUType cpuType: Int32) -> BinaryArchitecture? {
        switch cpuType {
        case 0x0100_0007: .intel        // CPU_TYPE_X86_64
        case 7: .intel                  // CPU_TYPE_I386
        case 0x0100_000C: .appleSilicon // CPU_TYPE_ARM64
        case 12: .appleSilicon          // CPU_TYPE_ARM
        default: nil
        }
    }

    /// Extracts the signing authority so the UI can show a real developer name
    /// instead of guessing from the bundle identifier.
    private static func signingAuthority(for bundleURL: URL) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["-dv", "--verbose=2", bundleURL.path]
        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = Pipe()

        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let text = String(data: data, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n") where line.hasPrefix("Authority=") {
            let authority = line.dropFirst("Authority=".count)
            // The leaf authority names the developer; skip Apple's chain entries.
            if authority.contains("Developer ID Application:") {
                return authority
                    .replacingOccurrences(of: "Developer ID Application: ", with: "")
                    .replacingOccurrences(of: #"\s*\([A-Z0-9]+\)$"#, with: "", options: .regularExpression)
            }
            if authority.hasPrefix("Software Signing") || authority.hasPrefix("Apple Mac OS") {
                return "Apple"
            }
            return String(authority)
        }
        return nil
    }

    // MARK: - Actions

    @MainActor
    public static func launch(_ app: InstalledApp) {
        NSWorkspace.shared.openApplication(
            at: app.url,
            configuration: NSWorkspace.OpenConfiguration()
        )
    }

    @MainActor
    public static func reveal(_ app: InstalledApp) {
        NSWorkspace.shared.activateFileViewerSelecting([app.url])
    }

    /// Running instances of a bundle, so Force Quit is only offered when it
    /// would actually do something.
    @MainActor
    public static func runningInstances(of app: InstalledApp) -> [NSRunningApplication] {
        guard let identifier = app.bundleIdentifier else { return [] }
        return NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
    }

    @MainActor
    @discardableResult
    public static func forceQuit(_ app: InstalledApp) -> Bool {
        let instances = runningInstances(of: app)
        guard !instances.isEmpty else { return false }
        return instances.allSatisfy { $0.forceTerminate() }
    }

    /// Moves a bundle to the Trash. Always confirmed by the caller first.
    ///
    /// Returns the failure reason, or nil on success. `recycle` is used rather
    /// than a delete so the action stays reversible from the Finder.
    @MainActor
    public static func moveToTrash(_ app: InstalledApp) async -> String? {
        await withCheckedContinuation { continuation in
            NSWorkspace.shared.recycle([app.url]) { _, error in
                continuation.resume(returning: error?.localizedDescription)
            }
        }
    }

    /// Sandbox container for the app, when one exists.
    public nonisolated func containerURL(for app: InstalledApp) -> URL? {
        guard let identifier = app.bundleIdentifier else { return nil }
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/\(identifier)", isDirectory: true)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Preferences plist for the app, when one exists.
    public nonisolated func preferencesURL(for app: InstalledApp) -> URL? {
        guard let identifier = app.bundleIdentifier else { return nil }
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/\(identifier).plist")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Privacy usage descriptions declared in the bundle.
    ///
    /// This is what the app *asks* for. Whether the user granted it lives in
    /// TCC.db, which is protected, so PulseMonitor reports the declaration only.
    public nonisolated func declaredPermissions(for app: InstalledApp) -> [(key: String, description: String)] {
        guard let bundle = Bundle(url: app.url), let info = bundle.infoDictionary else { return [] }
        return info
            .filter { $0.key.hasSuffix("UsageDescription") }
            .compactMap { key, value in
                guard let description = value as? String else { return nil }
                return (key: Self.friendlyPermissionName(key), description: description)
            }
            .sorted { $0.key < $1.key }
    }

    private static func friendlyPermissionName(_ key: String) -> String {
        key
            .replacingOccurrences(of: "NS", with: "")
            .replacingOccurrences(of: "UsageDescription", with: "")
            .replacingOccurrences(of: #"([a-z])([A-Z])"#, with: "$1 $2", options: .regularExpression)
    }

    /// Crash reports macOS has recorded for this bundle.
    public nonisolated func crashReports(for app: InstalledApp) -> [CrashReport] {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/DiagnosticReports", isDirectory: true)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return [] }

        let executableName = Bundle(url: app.url)?.executableURL?.lastPathComponent ?? app.name

        return entries
            .filter { $0.lastPathComponent.hasPrefix(executableName) }
            .compactMap { url in
                let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate
                return CrashReport(path: url.path, name: url.lastPathComponent, date: date ?? .distantPast)
            }
            .sorted { $0.date > $1.date }
    }

    public struct CrashReport: Sendable, Identifiable, Equatable {
        public var id: String { path }
        public let path: String
        public let name: String
        public let date: Date
    }
}

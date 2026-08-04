import Foundation

/// Imports/exports settings bundles matching `Shared/Schemas/sync-profile.schema.json`.
public actor SyncBundleService {
    public struct BundleDocument: Sendable, Codable {
        public var schemaVersion: String
        public var exportedAt: Date
        public var settings: Settings
        public var theme: String
        public var workspaces: [String]
        public var automationRules: [String]
        public var menuBarStudio: [String: String]?
        public var widgetBoard: [String]

        public struct Settings: Sendable, Codable {
            public var refreshIntervalSeconds: Double?
            public var overlayEnabled: Bool?
            public var notificationsEnabled: Bool?
            public var activeProfile: String?
        }
    }

    public init() {}

    public func exportURL(theme: String, profile: String, overlay: Bool, notifications: Bool, interval: Double) throws -> URL {
        let doc = BundleDocument(
            schemaVersion: "4.0.0",
            exportedAt: .now,
            settings: .init(
                refreshIntervalSeconds: interval,
                overlayEnabled: overlay,
                notificationsEnabled: notifications,
                activeProfile: profile
            ),
            theme: theme,
            workspaces: [],
            automationRules: [],
            menuBarStudio: nil,
            widgetBoard: []
        )
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("PulseMonitor/Sync", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("pulsemonitor-sync-\(Int(Date().timeIntervalSince1970)).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(doc).write(to: url)
        return url
    }

    public func importBundle(from url: URL) throws -> BundleDocument {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(BundleDocument.self, from: data)
    }
}

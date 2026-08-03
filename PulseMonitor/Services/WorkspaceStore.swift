import Foundation
import Observation

public struct Workspace: Sendable, Codable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var symbol: String
    public var sidebarItem: String
    public var profile: PowerProfile.Kind
    public var overlayEnabled: Bool
    public var theme: Theme
    public var refreshIntervalSeconds: Double
    public var widgetIDs: [UUID]

    public static let presets: [Workspace] = [
        .init(name: "Gaming", symbol: "gamecontroller", sidebarItem: SidebarItem.games.rawValue,
              profile: .gaming, overlayEnabled: true, theme: .midnight, refreshIntervalSeconds: 0.5, widgetIDs: []),
        .init(name: "Programming", symbol: "chevron.left.forwardslash.chevron.right", sidebarItem: SidebarItem.processes.rawValue,
              profile: .developer, overlayEnabled: false, theme: .developer, refreshIntervalSeconds: 1.0, widgetIDs: []),
        .init(name: "Battery Saving", symbol: "battery.50", sidebarItem: SidebarItem.battery.rawValue,
              profile: .batterySaver, overlayEnabled: false, theme: .apple, refreshIntervalSeconds: 5.0, widgetIDs: []),
        .init(name: "Monitoring", symbol: "gauge.with.dots.needle.67percent", sidebarItem: SidebarItem.dashboard.rawValue,
              profile: .balanced, overlayEnabled: false, theme: .apple, refreshIntervalSeconds: 1.0, widgetIDs: []),
        .init(name: "Streaming", symbol: "dot.radiowaves.left.and.right", sidebarItem: SidebarItem.network.rawValue,
              profile: .performance, overlayEnabled: true, theme: .tahoeDark, refreshIntervalSeconds: 1.0, widgetIDs: []),
        .init(name: "Editing", symbol: "slider.horizontal.3", sidebarItem: SidebarItem.gpu.rawValue,
              profile: .videoEditing, overlayEnabled: false, theme: .graphite, refreshIntervalSeconds: 1.0, widgetIDs: [])
    ]

    public init(
        id: UUID = UUID(),
        name: String,
        symbol: String,
        sidebarItem: String,
        profile: PowerProfile.Kind,
        overlayEnabled: Bool,
        theme: Theme,
        refreshIntervalSeconds: Double,
        widgetIDs: [UUID]
    ) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.sidebarItem = sidebarItem
        self.profile = profile
        self.overlayEnabled = overlayEnabled
        self.theme = theme
        self.refreshIntervalSeconds = refreshIntervalSeconds
        self.widgetIDs = widgetIDs
    }
}

@MainActor
@Observable
public final class WorkspaceStore {
    public var workspaces: [Workspace]
    public var activeID: UUID?

    private let defaults: UserDefaults
    private let key = "v3.workspaces"
    private let activeKey = "v3.activeWorkspace"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([Workspace].self, from: data),
           !decoded.isEmpty {
            workspaces = decoded
        } else {
            workspaces = Workspace.presets
        }
        if let raw = defaults.string(forKey: activeKey) {
            activeID = UUID(uuidString: raw)
        }
    }

    public func apply(_ workspace: Workspace, settings: AppSettings, profiles: PowerProfileService) -> SidebarItem? {
        profiles.apply(workspace.profile)
        settings.overlayEnabled = workspace.overlayEnabled
        settings.theme = workspace.theme
        settings.refreshIntervalSeconds = workspace.refreshIntervalSeconds
        activeID = workspace.id
        defaults.set(workspace.id.uuidString, forKey: activeKey)
        persist()
        return SidebarItem(rawValue: workspace.sidebarItem)
    }

    public func saveCurrent(
        name: String,
        symbol: String,
        sidebar: SidebarItem,
        settings: AppSettings
    ) {
        let workspace = Workspace(
            name: name,
            symbol: symbol,
            sidebarItem: sidebar.rawValue,
            profile: settings.activeProfile,
            overlayEnabled: settings.overlayEnabled,
            theme: settings.theme,
            refreshIntervalSeconds: settings.refreshIntervalSeconds,
            widgetIDs: []
        )
        workspaces.append(workspace)
        persist()
    }

    public func delete(_ id: UUID) {
        workspaces.removeAll { $0.id == id }
        if activeID == id { activeID = nil }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(workspaces) {
            defaults.set(data, forKey: key)
        }
    }
}

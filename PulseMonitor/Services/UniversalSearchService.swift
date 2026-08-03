import Foundation

public struct SearchHit: Identifiable, Equatable {
    public var id: String { "\(kind.rawValue)-\(title)-\(subtitle)" }
    public let kind: Kind
    public let title: String
    public let subtitle: String
    public let sidebarItem: SidebarItem?

    public enum Kind: String {
        case module, process, sensor, setting, hardware, log, command
    }
}

@MainActor
public struct UniversalSearchService {
    public init() {}

    public func search(
        query: String,
        processes: [ProcessInfoModel],
        hardware: HardwareInventory?,
        events: [SystemEvent],
        twin: DigitalTwinState?
    ) -> [SearchHit] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard q.count >= 1 else { return [] }
        var hits: [SearchHit] = []

        for item in SidebarItem.allCases where item.title.lowercased().contains(q) || item.rawValue.contains(q) {
            hits.append(.init(kind: .module, title: item.title, subtitle: "Open module", sidebarItem: item))
        }

        for process in processes where process.name.lowercased().contains(q) {
            hits.append(.init(
                kind: .process,
                title: process.name,
                subtitle: String(format: "PID %d · %.0f%% CPU", process.pid, process.cpuPercent),
                sidebarItem: .processes
            ))
            if hits.count > 40 { break }
        }

        if let twin {
            for component in twin.components where component.kind.displayName.lowercased().contains(q) {
                hits.append(.init(
                    kind: .sensor,
                    title: component.kind.displayName,
                    subtitle: component.available
                        ? (component.load.map { String(format: "%.0f%% load", $0) } ?? "Available")
                        : (component.unavailableReason ?? "Unavailable"),
                    sidebarItem: .digitalTwin
                ))
            }
        }

        if let hardware {
            for device in hardware.usbDevices + hardware.pciDevices + hardware.displays
            where device.name.lowercased().contains(q) {
                hits.append(.init(kind: .hardware, title: device.name, subtitle: device.detail, sidebarItem: .hardwareDB))
            }
        }

        for event in events.prefix(200)
        where event.title.lowercased().contains(q) || (event.detail?.lowercased().contains(q) ?? false) {
            hits.append(.init(kind: .log, title: event.title, subtitle: event.category.rawValue, sidebarItem: .logs))
            if hits.count > 60 { break }
        }

        let commands: [(String, String, SidebarItem)] = [
            ("snapshot", "Capture system snapshot", .snapshots),
            ("optimize", "Open Auto Optimizer", .optimizer),
            ("overlay", "Toggle performance overlay", .settings),
            ("benchmark", "Run benchmarks", .benchmarks),
            ("workspace", "Open workspaces", .workspaces)
        ]
        for command in commands where command.0.contains(q) || command.1.lowercased().contains(q) {
            hits.append(.init(kind: .command, title: command.1, subtitle: "Command", sidebarItem: command.2))
        }

        return Array(hits.prefix(80))
    }
}

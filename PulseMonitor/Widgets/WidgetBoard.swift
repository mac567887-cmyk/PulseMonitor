import Foundation
import Observation
import SwiftUI

/// Built-in widget kinds users can place on a custom dashboard.
public enum WidgetKind: String, CaseIterable, Identifiable, Codable, Sendable, Hashable {
    case cpuGauge
    case gpuGraph
    case ramGraph
    case thermals
    case diskSpeed
    case clock
    case calendar
    case battery
    case fanRPM
    case network
    case pluginSensors

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .cpuGauge: "CPU Gauge"
        case .gpuGraph: "GPU Graph"
        case .ramGraph: "RAM Graph"
        case .thermals: "Thermals"
        case .diskSpeed: "Disk Speed"
        case .clock: "Clock"
        case .calendar: "Calendar"
        case .battery: "Battery"
        case .fanRPM: "Fan RPM"
        case .network: "Network"
        case .pluginSensors: "Plugin Sensors"
        }
    }

    public var symbol: String {
        switch self {
        case .cpuGauge: "gauge.with.dots.needle.67percent"
        case .gpuGraph: "cube"
        case .ramGraph: "memorychip"
        case .thermals: "thermometer.medium"
        case .diskSpeed: "internaldrive"
        case .clock: "clock"
        case .calendar: "calendar"
        case .battery: "battery.100"
        case .fanRPM: "fan"
        case .network: "network"
        case .pluginSensors: "puzzlepiece.extension"
        }
    }

    public var defaultSize: WidgetSize {
        switch self {
        case .cpuGauge, .battery, .clock, .calendar, .fanRPM: .small
        case .gpuGraph, .ramGraph, .thermals, .diskSpeed, .network: .medium
        case .pluginSensors: .large
        }
    }
}

public enum WidgetSize: String, CaseIterable, Identifiable, Codable, Sendable {
    case small, medium, large

    public var id: String { rawValue }

    public var displayName: String { rawValue.capitalized }

    public var gridSpan: (columns: Int, rows: Int) {
        switch self {
        case .small: (1, 1)
        case .medium: (2, 1)
        case .large: (2, 2)
        }
    }
}

/// One placed widget on the custom board.
public struct WidgetPlacement: Identifiable, Codable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var kind: WidgetKind
    public var size: WidgetSize
    public var column: Int
    public var row: Int

    public init(
        id: UUID = UUID(),
        kind: WidgetKind,
        size: WidgetSize? = nil,
        column: Int = 0,
        row: Int = 0
    ) {
        self.id = id
        self.kind = kind
        self.size = size ?? kind.defaultSize
        self.column = column
        self.row = row
    }
}

/// Persisted layout for the Widgets module.
@MainActor
@Observable
public final class WidgetBoardStore {
    public var placements: [WidgetPlacement] {
        didSet { persist() }
    }

    public var isEditing: Bool = false

    private let defaults: UserDefaults
    private let key = "widgetBoard.placements"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([WidgetPlacement].self, from: data),
           !decoded.isEmpty {
            self.placements = decoded
        } else {
            self.placements = Self.defaultLayout
        }
    }

    public func add(_ kind: WidgetKind) {
        let nextRow = (placements.map(\.row).max() ?? -1) + 1
        placements.append(WidgetPlacement(kind: kind, column: 0, row: max(0, nextRow)))
    }

    public func remove(_ id: UUID) {
        placements.removeAll { $0.id == id }
    }

    public func resize(_ id: UUID, to size: WidgetSize) {
        guard let index = placements.firstIndex(where: { $0.id == id }) else { return }
        placements[index].size = size
    }

    public func move(from source: IndexSet, to destination: Int) {
        placements.move(fromOffsets: source, toOffset: destination)
    }

    public func reset() {
        placements = Self.defaultLayout
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(placements) {
            defaults.set(data, forKey: key)
        }
    }

    private static let defaultLayout: [WidgetPlacement] = [
        WidgetPlacement(kind: .cpuGauge, column: 0, row: 0),
        WidgetPlacement(kind: .ramGraph, column: 1, row: 0),
        WidgetPlacement(kind: .thermals, column: 0, row: 1),
        WidgetPlacement(kind: .battery, column: 1, row: 1),
        WidgetPlacement(kind: .clock, column: 0, row: 2),
        WidgetPlacement(kind: .network, column: 1, row: 2)
    ]
}

import Foundation
import Observation

/// One-click system snapshot for side-by-side comparison.
public struct SystemSnapshot: Sendable, Codable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var createdAt: Date
    public var metrics: SystemMetrics
    public var analysis: AnalysisReport?
    public var topProcesses: [ProcessInfoModel]
    public var notes: String

    public init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = .now,
        metrics: SystemMetrics,
        analysis: AnalysisReport?,
        topProcesses: [ProcessInfoModel],
        notes: String = ""
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.metrics = metrics
        self.analysis = analysis
        self.topProcesses = topProcesses
        self.notes = notes
    }
}

/// Diff between two snapshots — only fields that actually changed.
public struct SnapshotDiff: Sendable, Equatable, Identifiable {
    public var id: String { label }
    public let label: String
    public let before: String
    public let after: String
    public let direction: Direction

    public enum Direction: String, Sendable {
        case improved, worsened, changed
    }
}

@MainActor
@Observable
public final class SnapshotService {
    public private(set) var snapshots: [SystemSnapshot] = []

    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = support.appendingPathComponent("PulseMonitor", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("snapshots.json")
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        load()
    }

    public func capture(
        name: String? = nil,
        metrics: SystemMetrics,
        analysis: AnalysisReport?,
        processes: [ProcessInfoModel]
    ) {
        let stamp = Date.now.formatted(date: .abbreviated, time: .shortened)
        let snapshot = SystemSnapshot(
            name: name ?? "Snapshot \(stamp)",
            metrics: metrics,
            analysis: analysis,
            topProcesses: Array(processes.sorted { $0.cpuPercent > $1.cpuPercent }.prefix(20))
        )
        snapshots.insert(snapshot, at: 0)
        if snapshots.count > 80 { snapshots = Array(snapshots.prefix(80)) }
        persist()
    }

    public func delete(_ id: UUID) {
        snapshots.removeAll { $0.id == id }
        persist()
    }

    public func rename(_ id: UUID, to name: String) {
        guard let index = snapshots.firstIndex(where: { $0.id == id }) else { return }
        snapshots[index].name = name
        persist()
    }

    public func diff(_ a: SystemSnapshot, _ b: SystemSnapshot) -> [SnapshotDiff] {
        var rows: [SnapshotDiff] = []
        func add(_ label: String, before: String, after: String, improvedWhenLower: Bool = true) {
            guard before != after else { return }
            let direction: SnapshotDiff.Direction
            if let b = Double(before.replacingOccurrences(of: "%", with: "")),
               let a = Double(after.replacingOccurrences(of: "%", with: "")) {
                if a == b { direction = .changed }
                else if improvedWhenLower { direction = a < b ? .improved : .worsened }
                else { direction = a > b ? .improved : .worsened }
            } else {
                direction = .changed
            }
            rows.append(.init(label: label, before: before, after: after, direction: direction))
        }

        add("CPU", before: Formatters.percent(a.metrics.cpu.totalUsage), after: Formatters.percent(b.metrics.cpu.totalUsage))
        add("GPU", before: Formatters.percent(a.metrics.gpu.utilization), after: Formatters.percent(b.metrics.gpu.utilization))
        add("Memory", before: Formatters.percent(a.metrics.memory.usagePercent), after: Formatters.percent(b.metrics.memory.usagePercent))
        add("Swap", before: Formatters.bytes(a.metrics.memory.swapUsedBytes), after: Formatters.bytes(b.metrics.memory.swapUsedBytes))
        add("Thermal", before: a.metrics.thermal.thermalState.displayName, after: b.metrics.thermal.thermalState.displayName)
        add(
            "Health score",
            before: String(format: "%.0f", a.analysis?.overallHealthScore ?? 0),
            after: String(format: "%.0f", b.analysis?.overallHealthScore ?? 0),
            improvedWhenLower: false
        )
        add(
            "Top process",
            before: a.topProcesses.first.map { "\($0.name) \(Formatters.percent($0.cpuPercent))" } ?? "—",
            after: b.topProcesses.first.map { "\($0.name) \(Formatters.percent($0.cpuPercent))" } ?? "—"
        )
        return rows
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? decoder.decode([SystemSnapshot].self, from: data) else { return }
        snapshots = decoded
    }

    private func persist() {
        guard let data = try? encoder.encode(snapshots) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

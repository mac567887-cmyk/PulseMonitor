import Foundation
import Observation

public struct GameSessionSample: Sendable, Codable, Equatable {
    public let timestamp: Date
    public let cpu: Double
    public let gpu: Double?
    public let memoryBytes: UInt64
    public let temperatureC: Double?
    public let powerWatts: Double?
    public let diskReadBps: Double
    public let networkBps: Double
}

public struct GameLibraryEntry: Sendable, Codable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var platform: Platform
    public var bundlePath: String?
    public var samples: [GameSessionSample]
    public var notes: String

    public enum Platform: String, Sendable, Codable, CaseIterable {
        case steam, epic, heroic, minecraft, whisky, crossover, native, unknown

        public var displayName: String { rawValue.capitalized }
    }

    public var averageCPU: Double {
        guard !samples.isEmpty else { return 0 }
        return samples.map(\.cpu).reduce(0, +) / Double(samples.count)
    }

    public var averageGPU: Double? {
        let values = samples.compactMap(\.gpu)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    public var averageTemp: Double? {
        let values = samples.compactMap(\.temperatureC)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}

public struct ShaderSpikeEvent: Sendable, Codable, Equatable, Identifiable {
    public var id: UUID
    public let timestamp: Date
    public let processName: String
    public let cpuDelta: Double
    public let diskDelta: Double
    public let detail: String
}

public struct JavaRuntimeInsight: Sendable, Equatable, Identifiable {
    public var id: String { processName }
    public let processName: String
    public let pid: Int32
    public let threadCount: Int
    public let memoryBytes: UInt64
    public let cpuPercent: Double
    public let jvmFlags: [String]
    public let notes: [String]
}

@MainActor
@Observable
public final class GameLabService {
    public private(set) var library: [GameLibraryEntry] = []
    public private(set) var activeGames: [ProcessInfoModel] = []
    public private(set) var shaderSpikes: [ShaderSpikeEvent] = []
    public private(set) var javaInsights: [JavaRuntimeInsight] = []
    public private(set) var isRecording = false

    private var lastCPUByPID: [Int32: Double] = [:]
    private var lastDisk: Double = 0
    private let fileURL: URL

    public init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = support.appendingPathComponent("PulseMonitor", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("game-library.json")
        load()
    }

    public func ingest(
        metrics: SystemMetrics,
        processes: [ProcessInfoModel],
        detectedGames: [ProcessInfoModel]
    ) {
        activeGames = detectedGames
        detectShaderSpikes(metrics: metrics, games: detectedGames)
        updateJavaInsights(processes: processes)
        guard isRecording else { return }

        for game in detectedGames {
            let sample = GameSessionSample(
                timestamp: .now,
                cpu: game.cpuPercent,
                gpu: metrics.gpu.utilization,
                memoryBytes: game.memoryBytes,
                temperatureC: metrics.thermal.cpuTemperatureC,
                powerWatts: metrics.power.totalSystemWatts > 0 ? metrics.power.totalSystemWatts : nil,
                diskReadBps: metrics.storage.readBytesPerSec,
                networkBps: metrics.network.bytesInPerSec + metrics.network.bytesOutPerSec
            )
            upsert(game: game, sample: sample)
        }
        persist()
    }

    public func startRecording() { isRecording = true }
    public func stopRecording() { isRecording = false; persist() }

    public func performanceReport(for id: String) -> String {
        guard let entry = library.first(where: { $0.id == id }) else {
            return "No library entry yet. Enable recording while a game is running."
        }
        var lines = [
            "Game: \(entry.name)",
            "Platform: \(entry.platform.displayName)",
            String(format: "Avg CPU: %.1f%%", entry.averageCPU)
        ]
        if let gpu = entry.averageGPU {
            lines.append(String(format: "Avg GPU: %.1f%%", gpu))
        } else {
            lines.append("Avg GPU: unavailable (driver does not publish utilization)")
        }
        if let temp = entry.averageTemp {
            lines.append(String(format: "Avg CPU temp: %.0f°C", temp))
        }
        lines.append("Samples: \(entry.samples.count)")
        lines.append("FPS is not estimated — PulseMonitor does not invent frame rates.")
        return lines.joined(separator: "\n")
    }

    private func upsert(game: ProcessInfoModel, sample: GameSessionSample) {
        let id = game.bundleIdentifier ?? "\(game.name)-\(game.pid)"
        if let index = library.firstIndex(where: { $0.id == id }) {
            library[index].samples.append(sample)
            if library[index].samples.count > 2_000 {
                library[index].samples.removeFirst(library[index].samples.count - 2_000)
            }
        } else {
            library.append(
                GameLibraryEntry(
                    id: id,
                    name: game.name,
                    platform: Self.platform(for: game),
                    bundlePath: game.executablePath,
                    samples: [sample],
                    notes: ""
                )
            )
        }
    }

    private func detectShaderSpikes(metrics: SystemMetrics, games: [ProcessInfoModel]) {
        let disk = metrics.storage.readBytesPerSec + metrics.storage.writeBytesPerSec
        let diskDelta = disk - lastDisk
        lastDisk = disk

        for game in games {
            let previous = lastCPUByPID[game.pid] ?? game.cpuPercent
            let cpuDelta = game.cpuPercent - previous
            lastCPUByPID[game.pid] = game.cpuPercent

            // Heuristic only: sudden CPU + disk surge while a game is focused.
            if cpuDelta > 35, diskDelta > 20_000_000 {
                shaderSpikes.insert(
                    ShaderSpikeEvent(
                        id: UUID(),
                        timestamp: .now,
                        processName: game.name,
                        cpuDelta: cpuDelta,
                        diskDelta: diskDelta,
                        detail: "Sudden CPU and disk surge while a game is active — often shader compilation or asset streaming. This is a heuristic, not a Metal capture."
                    ),
                    at: 0
                )
                if shaderSpikes.count > 50 { shaderSpikes = Array(shaderSpikes.prefix(50)) }
            }
        }
    }

    private func updateJavaInsights(processes: [ProcessInfoModel]) {
        javaInsights = processes.compactMap { process in
            let name = process.name.lowercased()
            let path = (process.executablePath ?? "").lowercased()
            guard name.contains("java") || path.contains("java") || name.contains("minecraft") else { return nil }
            let flags: [String] = []
            var notes: [String] = [
                "Java heap and GC pause times require attaching to the JVM (jstat/jcmd) with permissions PulseMonitor does not assume.",
                "Thread count below is the process thread count from libproc, not the JVM's internal pool breakdown."
            ]
            if path.contains("minecraft") || name.contains("minecraft") {
                notes.append("Minecraft detected — chunk / entity spikes usually show up as CPU bursts correlated with disk reads.")
            }
            return JavaRuntimeInsight(
                processName: process.name,
                pid: process.pid,
                threadCount: process.threadCount,
                memoryBytes: process.memoryBytes,
                cpuPercent: process.cpuPercent,
                jvmFlags: flags,
                notes: notes
            )
        }
    }

    private static func platform(for process: ProcessInfoModel) -> GameLibraryEntry.Platform {
        let blob = ((process.executablePath ?? "") + process.name + (process.bundleIdentifier ?? "")).lowercased()
        if blob.contains("steam") { return .steam }
        if blob.contains("epic") { return .epic }
        if blob.contains("heroic") { return .heroic }
        if blob.contains("minecraft") || blob.contains("javaw") { return .minecraft }
        if blob.contains("whisky") || blob.contains("wine") { return .whisky }
        if blob.contains("crossover") { return .crossover }
        if process.bundleIdentifier != nil { return .native }
        return .unknown
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([GameLibraryEntry].self, from: data) else { return }
        library = decoded
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(library) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

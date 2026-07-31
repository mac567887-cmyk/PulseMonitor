import Foundation
import SQLite3

/// SQLite-backed historical metrics store with configurable retention.
public actor HistoryRepository {
    private var db: OpaquePointer?
    private let settings: AppSettings
    private let fileURL: URL

    public init(settings: AppSettings, fileURL: URL? = nil) {
        self.settings = settings
        let defaultURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("PulseMonitor", isDirectory: true)
            .appendingPathComponent("history.sqlite")
        self.fileURL = fileURL ?? defaultURL
        Task { await self.open() }
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    private func open() {
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if sqlite3_open(fileURL.path, &db) != SQLITE_OK {
            db = nil
            return
        }
        exec("""
        CREATE TABLE IF NOT EXISTS metrics (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp REAL NOT NULL,
            cpu REAL NOT NULL,
            gpu REAL NOT NULL,
            memory REAL NOT NULL,
            swap REAL NOT NULL,
            network_in REAL NOT NULL,
            network_out REAL NOT NULL,
            temperature REAL,
            thermal_state TEXT,
            payload BLOB
        );
        CREATE INDEX IF NOT EXISTS idx_metrics_ts ON metrics(timestamp);
        """)
    }

    public func insert(metrics: SystemMetrics) async {
        guard let db else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let payload = try? encoder.encode(metrics)

        let sql = """
        INSERT INTO metrics (timestamp, cpu, gpu, memory, swap, network_in, network_out, temperature, thermal_state, payload)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_double(statement, 1, metrics.timestamp.timeIntervalSince1970)
        sqlite3_bind_double(statement, 2, metrics.cpu.totalUsage)
        sqlite3_bind_double(statement, 3, metrics.gpu.utilization)
        sqlite3_bind_double(statement, 4, metrics.memory.usagePercent)
        sqlite3_bind_double(statement, 5, Double(metrics.memory.swapUsedBytes))
        sqlite3_bind_double(statement, 6, metrics.network.bytesInPerSec)
        sqlite3_bind_double(statement, 7, metrics.network.bytesOutPerSec)
        if let temp = metrics.thermal.cpuTemperatureC ?? metrics.thermal.batteryTemperatureC {
            sqlite3_bind_double(statement, 8, temp)
        } else {
            sqlite3_bind_null(statement, 8)
        }
        sqlite3_bind_text(statement, 9, metrics.thermal.thermalState.rawValue, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        if let payload {
            payload.withUnsafeBytes { raw in
                sqlite3_bind_blob(statement, 10, raw.baseAddress, Int32(payload.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            }
        } else {
            sqlite3_bind_null(statement, 10)
        }
        _ = sqlite3_step(statement)
        await prune()
    }

    public struct HistoryPoint: Sendable, Identifiable, Equatable {
        public var id: Double { timestamp.timeIntervalSince1970 }
        public let timestamp: Date
        public let cpu: Double
        public let gpu: Double
        public let memory: Double
        public let networkIn: Double
        public let networkOut: Double
        public let temperature: Double?
    }

    public func query(from: Date, to: Date) async -> [HistoryPoint] {
        guard let db else { return [] }
        let sql = """
        SELECT timestamp, cpu, gpu, memory, network_in, network_out, temperature
        FROM metrics WHERE timestamp BETWEEN ? AND ? ORDER BY timestamp ASC;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return [] }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, from.timeIntervalSince1970)
        sqlite3_bind_double(statement, 2, to.timeIntervalSince1970)

        var points: [HistoryPoint] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let ts = Date(timeIntervalSince1970: sqlite3_column_double(statement, 0))
            let temp: Double? = sqlite3_column_type(statement, 6) == SQLITE_NULL ? nil : sqlite3_column_double(statement, 6)
            points.append(
                HistoryPoint(
                    timestamp: ts,
                    cpu: sqlite3_column_double(statement, 1),
                    gpu: sqlite3_column_double(statement, 2),
                    memory: sqlite3_column_double(statement, 3),
                    networkIn: sqlite3_column_double(statement, 4),
                    networkOut: sqlite3_column_double(statement, 5),
                    temperature: temp
                )
            )
        }
        return points
    }

    public func recent(seconds: TimeInterval) async -> [HistoryPoint] {
        let to = Date()
        let from = to.addingTimeInterval(-seconds)
        return await query(from: from, to: to)
    }

    private func prune() async {
        let retention = await MainActor.run { settings.historyRetention.seconds }
        let cutoff = Date().addingTimeInterval(-retention).timeIntervalSince1970
        exec("DELETE FROM metrics WHERE timestamp < \(cutoff);")
    }

    private func exec(_ sql: String) {
        guard let db else { return }
        var error: UnsafeMutablePointer<CChar>?
        _ = sqlite3_exec(db, sql, nil, nil, &error)
        if let error {
            sqlite3_free(error)
        }
    }
}

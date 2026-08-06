import Foundation

/// Unified diagnostic report matching `Shared/Schemas/report.schema.json` (v4).
/// macOS and Windows both emit this shape so reports sync across platforms.
public struct CrossPlatformReport: Sendable, Codable {
    public let schemaVersion: String
    public let platform: String
    public let generatedAt: Date
    public let hardware: Hardware
    public let metrics: Metrics
    public let analysis: Analysis
    public let recommendations: [String]

    public struct Hardware: Sendable, Codable {
        public let modelIdentifier: String?
        public let cpuBrand: String?
        public let gpuName: String?
        public let memoryBytes: UInt64?
        public let osVersion: String
    }

    public struct Metrics: Sendable, Codable {
        public let cpuPercent: Double
        public let gpuPercent: Double?
        public let memoryPercent: Double
        public let thermalState: String
        public let batteryPercent: Double?
        public let diskReadBps: Double
        public let diskWriteBps: Double
        public let networkInBps: Double
        public let networkOutBps: Double
    }

    public struct Analysis: Sendable, Codable {
        public let overallHealthScore: Double
        public let narrative: String
        public let findings: [Finding]

        public struct Finding: Sendable, Codable {
            public let category: String
            public let severity: String
            public let title: String
            public let summary: String
            public let recommendations: [String]
        }
    }

    public static func from(payload: ReportExporter.ReportPayload) -> CrossPlatformReport {
        let m = payload.metrics
        return CrossPlatformReport(
            schemaVersion: "5.0.0",
            platform: "macOS",
            generatedAt: payload.generatedAt,
            hardware: .init(
                modelIdentifier: payload.hardware.modelIdentifier,
                cpuBrand: payload.hardware.cpuBrand,
                gpuName: payload.hardware.gpuName,
                memoryBytes: payload.hardware.memoryBytes,
                osVersion: ProcessInfo.processInfo.operatingSystemVersionString
            ),
            metrics: .init(
                cpuPercent: m.cpu.totalUsage,
                gpuPercent: m.gpu.utilization,
                memoryPercent: m.memory.usagePercent,
                thermalState: m.thermal.thermalState.rawValue,
                batteryPercent: m.battery.chargePercent,
                diskReadBps: m.storage.readBytesPerSec,
                diskWriteBps: m.storage.writeBytesPerSec,
                networkInBps: m.network.bytesInPerSec,
                networkOutBps: m.network.bytesOutPerSec
            ),
            analysis: .init(
                overallHealthScore: payload.analysis.overallHealthScore,
                narrative: payload.analysis.narrative,
                findings: payload.analysis.findings.map {
                    .init(
                        category: $0.category.rawValue,
                        severity: $0.severity.rawValue,
                        title: $0.title,
                        summary: $0.summary,
                        recommendations: $0.recommendations
                    )
                }
            ),
            recommendations: payload.recommendations
        )
    }
}

import Foundation
import AppKit
import Darwin

/// Exports diagnostic reports as JSON, CSV, or printable PDF.
public actor ReportExporter {
    public init() {}

    public struct ReportPayload: Sendable, Codable {
        public let generatedAt: Date
        public let hardware: HardwareSummary
        public let metrics: SystemMetrics
        public let analysis: AnalysisReport
        public let topProcesses: [ProcessInfoModel]
        public let recommendations: [String]
    }

    public struct HardwareSummary: Sendable, Codable {
        public let cpuBrand: String
        public let architecture: String
        public let memoryBytes: UInt64
        public let gpuName: String
        public let modelIdentifier: String
    }

    public func build(
        metrics: SystemMetrics,
        analysis: AnalysisReport,
        processes: [ProcessInfoModel]
    ) -> ReportPayload {
        ReportPayload(
            generatedAt: .now,
            hardware: HardwareSummary(
                cpuBrand: metrics.cpu.brand,
                architecture: metrics.cpu.architecture.rawValue,
                memoryBytes: metrics.memory.totalBytes,
                gpuName: metrics.gpu.deviceName,
                modelIdentifier: Self.modelIdentifier()
            ),
            metrics: metrics,
            analysis: analysis,
            topProcesses: Array(processes.prefix(25)),
            recommendations: analysis.findings.flatMap(\.recommendations)
        )
    }

    public func exportJSON(_ report: ReportPayload, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(report).write(to: url)
    }

    public func exportCSV(_ report: ReportPayload, to url: URL) throws {
        var lines = ["metric,value"]
        lines.append("cpu_percent,\(report.metrics.cpu.totalUsage)")
        lines.append("gpu_percent,\(report.metrics.gpu.utilization)")
        lines.append("memory_percent,\(report.metrics.memory.usagePercent)")
        lines.append("swap_bytes,\(report.metrics.memory.swapUsedBytes)")
        lines.append("thermal_state,\(report.metrics.thermal.thermalState.rawValue)")
        lines.append("network_in_bps,\(report.metrics.network.bytesInPerSec)")
        lines.append("network_out_bps,\(report.metrics.network.bytesOutPerSec)")
        lines.append("health_score,\(report.analysis.overallHealthScore)")
        lines.append("primary_bottleneck,\(report.analysis.primaryBottleneck?.title ?? "None")")
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    public func exportPDF(_ report: ReportPayload, to url: URL) throws {
        let content = """
        PulseMonitor Diagnostic Report
        Generated: \(report.generatedAt.formatted())

        Hardware
        --------
        Model: \(report.hardware.modelIdentifier)
        CPU: \(report.hardware.cpuBrand)
        GPU: \(report.hardware.gpuName)
        Memory: \(Formatters.bytes(report.hardware.memoryBytes))

        Analysis
        --------
        \(report.analysis.narrative)

        Health Score: \(String(format: "%.0f", report.analysis.overallHealthScore))/100

        Findings
        --------
        \(report.analysis.findings.map { "• [\($0.severity.rawValue)] \($0.title): \($0.summary)" }.joined(separator: "\n"))

        Recommendations
        ---------------
        \(report.recommendations.map { "• \($0)" }.joined(separator: "\n"))
        """
        let data = Data(content.utf8)
        // Lightweight text-based PDF substitute for environments without print panel interaction.
        // Prefer true PDF via NSTextView when AppKit is available on main actor.
        let pdf = Self.simplePDF(from: content)
        try (pdf ?? data).write(to: url)
    }

    private static func simplePDF(from text: String) -> Data? {
        let pageWidth: CGFloat = 612
        let pageHeight: CGFloat = 792
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: pageWidth - 72, height: pageHeight - 72))
        view.string = text
        view.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        return view.dataWithPDF(inside: view.bounds)
    }

    private static func modelIdentifier() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var buffer = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.model", &buffer, &size, nil, 0)
        return String(cString: buffer)
    }
}

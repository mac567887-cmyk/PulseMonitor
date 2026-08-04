import Foundation
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
        // v4 unified schema shared with the Windows edition (`Shared/Schemas/report.schema.json`).
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(CrossPlatformReport.from(payload: report)).write(to: url)
    }

    public func exportCSV(_ report: ReportPayload, to url: URL) throws {
        var lines = ["metric,value"]
        lines.append("cpu_percent,\(report.metrics.cpu.totalUsage)")
        // Left empty rather than zero when the driver publishes no counter, so a
        // spreadsheet does not average in a load that was never measured.
        let gpuPercent = report.metrics.gpu.utilization.map { String($0) } ?? ""
        lines.append("gpu_percent,\(gpuPercent)")
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
        // Minimal valid single-page PDF embedding the text as a stream.
        let escaped = content
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "(", with: "\\(")
            .replacingOccurrences(of: ")", with: "\\)")
        let lines = escaped.components(separatedBy: "\n")
        var textOps = "BT /F1 10 Tf 50 740 Td 14 TL\n"
        for (idx, line) in lines.prefix(48).enumerated() {
            if idx == 0 {
                textOps += "(\(line)) Tj\n"
            } else {
                textOps += "T* (\(line)) Tj\n"
            }
        }
        textOps += "ET"
        let stream = textOps
        let objs: [String] = [
            "1 0 obj<< /Type /Catalog /Pages 2 0 R >>endobj\n",
            "2 0 obj<< /Type /Pages /Kids [3 0 R] /Count 1 >>endobj\n",
            "3 0 obj<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources<< /Font<< /F1 5 0 R >> >> >>endobj\n",
            "4 0 obj<< /Length \(stream.utf8.count) >>stream\n\(stream)\nendstream\nendobj\n",
            "5 0 obj<< /Type /Font /Subtype /Type1 /BaseFont /Courier >>endobj\n"
        ]
        var pdf = "%PDF-1.4\n"
        var offsets: [Int] = [0]
        for obj in objs {
            offsets.append(pdf.utf8.count)
            pdf += obj
        }
        let xref = pdf.utf8.count
        pdf += "xref\n0 \(objs.count + 1)\n"
        pdf += "0000000000 65535 f \n"
        for off in offsets.dropFirst() {
            pdf += String(format: "%010d 00000 n \n", off)
        }
        pdf += "trailer<< /Size \(objs.count + 1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"
        try Data(pdf.utf8).write(to: url)
    }

    private static func modelIdentifier() -> String {
        Sysctl.string("hw.model") ?? "Unknown Mac"
    }
}

import SwiftUI
import UniformTypeIdentifiers
import AppKit

public struct ReportsView: View {
    let container: AppContainer
    @State private var statusMessage = "Export a local diagnostic report. Nothing leaves this Mac."

    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionHeader("Reports", subtitle: "PDF · JSON · CSV")
            Text(statusMessage)
                .foregroundStyle(.secondary)
            HStack {
                Button("Export JSON") { export(kind: .json) }
                Button("Export CSV") { export(kind: .csv) }
                Button("Export PDF") { export(kind: .pdf) }
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AmbientBackground())
    }

    private enum Kind { case json, csv, pdf }

    private func export(kind: Kind) {
        guard let metrics = container.metricsCollector.latestMetrics,
              let analysis = container.metricsCollector.latestAnalysis else {
            statusMessage = "Wait for the first metrics sample."
            return
        }
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        switch kind {
        case .json:
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = "PulseMonitor-Report.json"
        case .csv:
            panel.allowedContentTypes = [.commaSeparatedText]
            panel.nameFieldStringValue = "PulseMonitor-Report.csv"
        case .pdf:
            panel.allowedContentTypes = [.pdf]
            panel.nameFieldStringValue = "PulseMonitor-Report.pdf"
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }

        Task {
            let report = await container.reportExporter.build(
                metrics: metrics,
                analysis: analysis,
                processes: container.metricsCollector.latestProcesses
            )
            do {
                switch kind {
                case .json:
                    try await container.reportExporter.exportJSON(report, to: url)
                case .csv:
                    try await container.reportExporter.exportCSV(report, to: url)
                case .pdf:
                    try await container.reportExporter.exportPDF(report, to: url)
                }
                await MainActor.run { statusMessage = "Saved to \(url.path)" }
            } catch {
                await MainActor.run { statusMessage = "Export failed: \(error.localizedDescription)" }
            }
        }
    }
}

import AppIntents
import AppKit
import Foundation

/// Shared helper that resolves the running app container for Shortcuts.
@MainActor
enum IntentSupport {
    static func container() throws -> AppContainer {
        guard let container = SharedAppContext.container else {
            throw IntentError.appNotRunning
        }
        return container
    }

    static func snapshotURL(prefix: String, ext: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("PulseMonitor-\(prefix)-\(Int(Date().timeIntervalSince1970)).\(ext)")
    }
}

enum IntentError: Error, CustomLocalizedStringResourceConvertible {
    case appNotRunning
    case exportFailed(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .appNotRunning:
            "PulseMonitor is not running. Open the app, then try the Shortcut again."
        case .exportFailed(let detail):
            "Export failed: \(detail)"
        }
    }
}

struct StartMonitoringIntent: AppIntent {
    static var title: LocalizedStringResource { "Start Monitoring" }
    static var description: IntentDescription {
        IntentDescription("Starts PulseMonitor’s metric collector if it is idle.")
    }
    static var openAppWhenRun: Bool { true }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await MainActor.run { try IntentSupport.container().start() }
        return .result(dialog: IntentDialog("Monitoring is running."))
    }
}

struct EnableOverlayIntent: AppIntent {
    static var title: LocalizedStringResource { "Enable Performance Overlay" }
    static var description: IntentDescription {
        IntentDescription("Shows the floating performance overlay.")
    }
    static var openAppWhenRun: Bool { true }

    @Parameter(title: "Enabled")
    var enabled: Bool

    init() { enabled = true }
    init(enabled: Bool) { self.enabled = enabled }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await MainActor.run {
            try IntentSupport.container().settings.overlayEnabled = enabled
        }
        return .result(dialog: IntentDialog(enabled ? "Overlay enabled." : "Overlay disabled."))
    }
}

struct RunBenchmarkIntent: AppIntent {
    static var title: LocalizedStringResource { "Run Benchmark" }
    static var description: IntentDescription {
        IntentDescription("Runs the PulseMonitor benchmark suite.")
    }
    static var openAppWhenRun: Bool { true }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let viewModel = try await MainActor.run { try IntentSupport.container().benchmarkViewModel }
        await viewModel.runAll()
        return .result(dialog: IntentDialog("Benchmark suite finished."))
    }
}

struct OptimizeSystemIntent: AppIntent {
    static var title: LocalizedStringResource { "Optimize System" }
    static var description: IntentDescription {
        IntentDescription(
            "Refreshes Auto Optimizer suggestions. Destructive actions still require confirmation in the app."
        )
    }
    static var openAppWhenRun: Bool { true }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let viewModel = try await MainActor.run { try IntentSupport.container().optimizerViewModel }
        await viewModel.analyze()
        return .result(dialog: IntentDialog(
            "Optimizer suggestions refreshed. Review them in PulseMonitor before applying."
        ))
    }
}

struct CreateSnapshotIntent: AppIntent {
    static var title: LocalizedStringResource { "Create Snapshot" }
    static var description: IntentDescription {
        IntentDescription("Exports a JSON snapshot of the latest metrics.")
    }
    static var openAppWhenRun: Bool { true }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let path = try await IntentExport.write(extension: "json") { exporter, report, url in
            try await exporter.exportJSON(report, to: url)
        }
        return .result(value: path, dialog: IntentDialog("Snapshot saved."))
    }
}

struct ExportReportIntent: AppIntent {
    static var title: LocalizedStringResource { "Export Report" }
    static var description: IntentDescription {
        IntentDescription("Exports a PDF diagnostic report.")
    }
    static var openAppWhenRun: Bool { true }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let path = try await IntentExport.write(extension: "pdf") { exporter, report, url in
            try await exporter.exportPDF(report, to: url)
        }
        return .result(value: path, dialog: IntentDialog("Report exported."))
    }
}

private enum IntentExport {
    static func write(
        extension ext: String,
        body: (ReportExporter, ReportExporter.ReportPayload, URL) async throws -> Void
    ) async throws -> String {
        let container = try await MainActor.run { try IntentSupport.container() }
        let metrics = await MainActor.run { container.metricsCollector.latestMetrics }
        guard let metrics else {
            throw IntentError.exportFailed("No samples available yet.")
        }
        let analysis = await MainActor.run { container.metricsCollector.latestAnalysis }
            ?? AnalysisReport(
                timestamp: .now,
                findings: [],
                primaryBottleneck: nil,
                overallHealthScore: 100,
                narrative: "No analysis yet."
            )
        let processes = await MainActor.run { container.metricsCollector.latestProcesses }
        let report = await container.reportExporter.build(
            metrics: metrics,
            analysis: analysis,
            processes: processes
        )
        let url = await MainActor.run { IntentSupport.snapshotURL(prefix: "report", ext: ext) }
        try await body(container.reportExporter, report, url)
        await MainActor.run { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        return url.path
    }
}

/// Registers the intents with Shortcuts.
struct PulseMonitorShortcuts: AppShortcutsProvider {
    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartMonitoringIntent(),
            phrases: ["Start monitoring with \(.applicationName)"],
            shortTitle: "Start Monitoring",
            systemImageName: "play.circle"
        )
        AppShortcut(
            intent: EnableOverlayIntent(),
            phrases: ["Show \(.applicationName) overlay"],
            shortTitle: "Enable Overlay",
            systemImageName: "rectangle.on.rectangle.angled"
        )
        AppShortcut(
            intent: RunBenchmarkIntent(),
            phrases: ["Run \(.applicationName) benchmark"],
            shortTitle: "Run Benchmark",
            systemImageName: "speedometer"
        )
        AppShortcut(
            intent: OptimizeSystemIntent(),
            phrases: ["Optimize Mac with \(.applicationName)"],
            shortTitle: "Optimize System",
            systemImageName: "wand.and.stars"
        )
        AppShortcut(
            intent: CreateSnapshotIntent(),
            phrases: ["Create \(.applicationName) snapshot"],
            shortTitle: "Create Snapshot",
            systemImageName: "camera.viewfinder"
        )
        AppShortcut(
            intent: ExportReportIntent(),
            phrases: ["Export \(.applicationName) report"],
            shortTitle: "Export Report",
            systemImageName: "doc.richtext"
        )
    }
}

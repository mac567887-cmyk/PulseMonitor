import Foundation
import AppKit

/// One suggested change, with an action the user must explicitly confirm.
public struct OptimizationSuggestion: Sendable, Identifiable, Equatable {
    public enum Impact: String, Sendable, Comparable {
        case low, medium, high

        private var rank: Int {
            switch self {
            case .low: 0
            case .medium: 1
            case .high: 2
            }
        }

        public static func < (lhs: Impact, rhs: Impact) -> Bool { lhs.rank < rhs.rank }

        public var displayName: String { rawValue.capitalized }
    }

    /// What the user can do about a suggestion.
    ///
    /// `manual` covers everything PulseMonitor refuses to automate; the app
    /// explains the step and, where possible, opens the right place for it.
    public enum Action: Sendable, Equatable {
        case quitProcess(pid: Int32, name: String)
        case openLoginItemsSettings
        case revealInFinder(path: String)
        case openTrash
        case manual
    }

    public let id: UUID
    public let title: String
    public let detail: String
    public let impact: Impact
    public let action: Action
    public let actionLabel: String?
    public let isDestructive: Bool

    public init(
        id: UUID = UUID(),
        title: String,
        detail: String,
        impact: Impact,
        action: Action = .manual,
        actionLabel: String? = nil,
        isDestructive: Bool = false
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.impact = impact
        self.action = action
        self.actionLabel = actionLabel
        self.isDestructive = isDestructive
    }
}

/// Inspects a metrics snapshot and proposes concrete, reversible changes.
///
/// Nothing here acts on its own. The optimizer produces suggestions; the user
/// decides. Anything that would delete data is flagged destructive and only ever
/// opens the relevant Finder location rather than removing files itself.
public struct AutoOptimizer: Sendable {
    public init() {}

    public func suggestions(
        metrics: SystemMetrics,
        processes: [ProcessInfoModel],
        launchAgentCount: Int
    ) -> [OptimizationSuggestion] {
        var results: [OptimizationSuggestion] = []

        results.append(contentsOf: cpuSuggestions(metrics: metrics, processes: processes))
        results.append(contentsOf: memorySuggestions(metrics: metrics, processes: processes))
        results.append(contentsOf: storageSuggestions(metrics: metrics))
        results.append(contentsOf: thermalSuggestions(metrics: metrics))
        results.append(contentsOf: networkSuggestions(metrics: metrics, processes: processes))

        if launchAgentCount > 8 {
            results.append(.init(
                title: "Review \(launchAgentCount) login items",
                detail: """
                \(launchAgentCount) launch agents start automatically for your account. Each one \
                costs memory and slows login. Removing the ones you no longer use is the single \
                most reliable way to shorten startup time.
                """,
                impact: launchAgentCount > 15 ? .high : .medium,
                action: .openLoginItemsSettings,
                actionLabel: "Open Login Items"
            ))
        }

        if results.isEmpty {
            results.append(.init(
                title: "Nothing worth changing right now",
                detail: """
                CPU, memory, storage, thermals and network are all within normal ranges. \
                There is no optimisation that would produce a measurable improvement.
                """,
                impact: .low
            ))
        }

        return results.sorted { $0.impact > $1.impact }
    }

    // MARK: - Rules

    private func cpuSuggestions(
        metrics: SystemMetrics,
        processes: [ProcessInfoModel]
    ) -> [OptimizationSuggestion] {
        guard metrics.cpu.totalUsage > 65 else { return [] }

        // Anything sustained above a fifth of a core is worth naming.
        let heavy = processes
            .filter { $0.cpuPercent > 20 }
            .sorted { $0.cpuPercent > $1.cpuPercent }
            .prefix(4)

        return heavy.map { process in
            OptimizationSuggestion(
                title: "\(process.name) is using \(Int(process.cpuPercent))% CPU",
                detail: """
                \(process.name) (PID \(process.pid)) is consuming \(String(format: "%.0f", process.cpuPercent))% \
                of a core's worth of CPU time. Quitting it would free that capacity immediately. \
                Save any open work first — this asks the process to terminate.
                """,
                impact: process.cpuPercent > 80 ? .high : .medium,
                action: .quitProcess(pid: process.pid, name: process.name),
                actionLabel: "Quit \(process.name)",
                isDestructive: true
            )
        }
    }

    private func memorySuggestions(
        metrics: SystemMetrics,
        processes: [ProcessInfoModel]
    ) -> [OptimizationSuggestion] {
        var results: [OptimizationSuggestion] = []
        let memory = metrics.memory

        if memory.pressure != .normal {
            let hogs = processes
                .sorted { $0.memoryBytes > $1.memoryBytes }
                .prefix(3)
                .map { "\($0.name) (\(Formatters.bytes(UInt64($0.memoryBytes))))" }
                .joined(separator: ", ")

            results.append(.init(
                title: "Memory pressure is \(memory.pressure.displayName.lowercased())",
                detail: """
                macOS is compressing memory to keep applications running. The largest consumers \
                are \(hogs). Closing one of them, or any browser window you are not reading, \
                will bring pressure back to normal faster than anything else.
                """,
                impact: memory.pressure == .critical ? .high : .medium
            ))
        }

        if memory.swapUsedBytes > 2_000_000_000 {
            results.append(.init(
                title: "Swap has grown to \(Formatters.bytes(UInt64(memory.swapUsedBytes)))",
                detail: """
                Your Mac has moved \(Formatters.bytes(UInt64(memory.swapUsedBytes))) of memory to disk. \
                Reads from swap are far slower than RAM, which is felt as stutter when switching apps. \
                Swap only shrinks after the memory that caused it is released, so closing a large \
                application is the fix.
                """,
                impact: .high
            ))
        }

        // Browsers are almost always the biggest single lever available.
        let browsers = ["Google Chrome", "Safari", "Firefox", "Microsoft Edge", "Brave Browser", "Arc"]
        let browserMemory = processes
            .filter { process in browsers.contains { process.name.contains($0) } }
            .reduce(into: UInt64(0)) { $0 += $1.memoryBytes }

        if browserMemory > 3_000_000_000 {
            results.append(.init(
                title: "Browsers are holding \(Formatters.bytes(UInt64(browserMemory)))",
                detail: """
                Browser processes account for \(Formatters.bytes(UInt64(browserMemory))) of memory. \
                Each open tab keeps its own renderer alive. Closing tabs you have finished with, \
                or letting the browser discard background tabs, recovers most of this without \
                quitting the browser.
                """,
                impact: .medium
            ))
        }

        return results
    }

    private func storageSuggestions(metrics: SystemMetrics) -> [OptimizationSuggestion] {
        var results: [OptimizationSuggestion] = []

        for volume in metrics.storage.volumes where volume.isRoot {
            if volume.usedPercent > 85 {
                results.append(.init(
                    title: "\(volume.name) is \(Int(volume.usedPercent))% full",
                    detail: """
                    Only \(Formatters.bytes(UInt64(volume.freeBytes))) remains on \(volume.name). \
                    macOS needs free space for swap and temporary files, and an SSD slows measurably \
                    once it passes about 90% capacity. Emptying the Trash is the safest place to start.
                    """,
                    impact: volume.usedPercent > 93 ? .high : .medium,
                    action: .openTrash,
                    actionLabel: "Open Trash"
                ))
            }
        }

        let caches = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches", isDirectory: true)
        if let size = Self.directorySize(caches, limit: 40_000), size > 5_000_000_000 {
            results.append(.init(
                title: "User caches occupy at least \(Formatters.bytes(size))",
                detail: """
                Your user cache folder holds at least \(Formatters.bytes(size)). Applications rebuild \
                these files on demand, so removing individual app folders is usually safe — but \
                PulseMonitor will not delete them for you. Review the folder and decide yourself.
                """,
                impact: .low,
                action: .revealInFinder(path: caches.path),
                actionLabel: "Reveal in Finder"
            ))
        }

        return results
    }

    private func thermalSuggestions(metrics: SystemMetrics) -> [OptimizationSuggestion] {
        var results: [OptimizationSuggestion] = []

        if metrics.thermal.isThrottling {
            results.append(.init(
                title: "Your Mac is thermally throttled right now",
                detail: """
                macOS has cut clock speed to shed heat\(metrics.thermal.throttleReason.map { ": \($0)" } ?? "."). \
                Performance will stay reduced until temperature falls. Raising the machine so air \
                can reach the underside vents, and reducing sustained CPU load, both help within \
                a minute or two.
                """,
                impact: .high
            ))
        }

        if let cpuTemp = metrics.thermal.cpuTemperatureC, cpuTemp > 90 {
            let fanNote: String
            let fans = metrics.thermal.fanSpeedsRPM
            if fans.isEmpty {
                fanNote = "No fan readings are available on this machine."
            } else {
                let atMaximum = fans.allSatisfy { fan in
                    guard let maxRPM = fan.maxRPM else { return false }
                    return fan.rpm > maxRPM * 0.9
                }
                fanNote = atMaximum
                    ? "The fans are already near maximum, so cooling capacity is the limit rather than fan speed."
                    : "The fans still have headroom, so heat is building faster than airflow can remove it."
            }

            results.append(.init(
                title: "CPU is running at \(Int(cpuTemp))°C",
                detail: "\(fanNote) Sustained temperatures above 90°C usually mean a long-running compile, render or game rather than a fault.",
                impact: cpuTemp > 98 ? .high : .medium
            ))
        }

        return results
    }

    private func networkSuggestions(
        metrics: SystemMetrics,
        processes: [ProcessInfoModel]
    ) -> [OptimizationSuggestion] {
        // 4 MB/s sustained is enough to interfere with interactive work on most links.
        guard metrics.network.bytesInPerSec > 4_000_000 else { return [] }

        let syncNames = ["Dropbox", "OneDrive", "Google Drive", "bird", "Backblaze", "Creative Cloud", "iCloud"]
        let running = processes
            .filter { process in syncNames.contains { process.name.localizedCaseInsensitiveContains($0) } }
            .map(\.name)

        guard !running.isEmpty else { return [] }

        return [.init(
            title: "Cloud sync is using the network heavily",
            detail: """
            \(running.joined(separator: ", ")) \(running.count == 1 ? "is" : "are") running while your \
            Mac is downloading \(Formatters.bytes(UInt64(metrics.network.bytesInPerSec)))/s. Pausing sync \
            from the app's own menu bar item frees bandwidth without losing anything — it resumes \
            where it left off.
            """,
            impact: .medium
        )]
    }

    // MARK: - Helpers

    /// Sums file sizes under a directory, stopping after `limit` entries so a
    /// huge tree cannot stall the optimiser.
    private static func directorySize(_ url: URL, limit: Int) -> UInt64? {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        var total: UInt64 = 0
        var visited = 0
        for case let fileURL as URL in enumerator {
            visited += 1
            if visited > limit { break }
            let values = try? fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey])
            total += UInt64(max(0, values?.totalFileAllocatedSize ?? 0))
        }
        return total
    }

    /// Performs a suggestion's action. Destructive actions are expected to have
    /// been confirmed by the caller already.
    @MainActor
    public static func perform(_ suggestion: OptimizationSuggestion) -> String? {
        switch suggestion.action {
        case .quitProcess(let pid, let name):
            guard let app = NSRunningApplication(processIdentifier: pid) else {
                // Non-GUI processes get a polite SIGTERM; no force killing.
                return kill(pid, SIGTERM) == 0 ? nil : "Could not signal \(name)."
            }
            return app.terminate() ? nil : "\(name) refused to quit."

        case .openLoginItemsSettings:
            if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
                NSWorkspace.shared.open(url)
            }
            return nil

        case .revealInFinder(let path):
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            return nil

        case .openTrash:
            let trash = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
            NSWorkspace.shared.open(trash)
            return nil

        case .manual:
            return nil
        }
    }
}

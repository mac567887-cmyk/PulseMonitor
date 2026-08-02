import Foundation

/// Detects games and compatibility/emulator runtimes and prepares game-focused analysis.
public actor GameDetector {
    /// Stored pre-lowercased; this list is matched against every running process on
    /// each sampling tick, so lowercasing here rather than per comparison matters.
    private static let knownNames: [String] = [
        "steam", "minecraft", "java", "heroic", "epic games", "whisky", "wine", "crossover",
        "ryujinx", "rpcs3", "pcsx2", "cemu", "dolphin", "yuzu", "suyu", "sudachi",
        "openemu", "parallels", "battle.net", "riot client", "leagueclient", "valorant",
        "cs2", "dota2", "genshin", "roblox", "unity", "unreal"
    ]

    private static let pathHints: [String] = [
        "/Steam/", "/Minecraft/", "/Heroic/", "/Epic Games/", "/Whisky/", "/Wine/",
        "/CrossOver/", "/Ryujinx/", "/RPCS3/", "/PCSX2/", "/Cemu/", "/Dolphin/",
        "/Applications/Games/"
    ]

    public init() {}

    /// `ProcessService` already resolves `isGame` once per PID and caches it, so
    /// this filters on that result instead of re-running the string matching for
    /// every process on every tick.
    public func detect(in processes: [ProcessInfoModel]) async -> [ProcessInfoModel] {
        processes.filter(\.isGame)
    }

    public func analyzeGamePerformance(
        game: ProcessInfoModel,
        metrics: SystemMetrics,
        background: [ProcessInfoModel]
    ) -> BottleneckFinding {
        let bgCPU = background.filter { !$0.isGame && $0.cpuPercent > 10 }
        var recommendations: [String] = []
        var detail = ExplanationGenerator.gameSpecificAdvice(for: game.name)

        let gpuLoad = metrics.gpu.utilization
        if metrics.cpu.totalUsage > 90, let gpuLoad, gpuLoad < 50 {
            detail += " Frame rate is likely CPU-limited."
            recommendations.append("Reduce simulation quality settings before graphics presets.")
        } else if let gpuLoad, gpuLoad > 90 {
            detail += " Frame rate is likely GPU-limited."
            recommendations.append("Lower resolution, shadows, or anti-aliasing.")
        } else if metrics.cpu.totalUsage > 90 {
            detail += " The CPU is saturated; this GPU publishes no load counter, so the limiter cannot be confirmed."
            recommendations.append("Compare frame rate with graphics settings lowered to test which side is limiting.")
        }
        if metrics.thermal.isThrottling {
            detail += " Thermal throttling is reducing clocks mid-session."
            recommendations.append("Improve cooling before increasing settings.")
        }
        if !bgCPU.isEmpty {
            recommendations.append("Quit background apps: \(bgCPU.prefix(3).map(\.name).joined(separator: ", ")).")
        }

        // No frame rate is reported here. Deriving one from CPU and GPU load would
        // be a guess dressed up as a measurement, and reading another process's
        // actual frame timing needs private APIs.

        return BottleneckFinding(
            id: UUID(),
            category: .game,
            severity: metrics.cpu.totalUsage > 90 || (gpuLoad ?? 0) > 90 ? .warning : .info,
            title: "Game Analysis: \(game.name)",
            summary: String(format: "%@ is active (CPU %.0f%%).", game.name, game.cpuPercent),
            detail: detail,
            relatedProcesses: [game.name] + bgCPU.prefix(3).map(\.name),
            recommendations: recommendations,
            detectedAt: .now,
            confidence: 0.7
        )
    }

    /// Called once per new PID from `ProcessService`, never on the hot path.
    ///
    /// Checks are ordered cheapest-first and each candidate string is lowercased
    /// at most once, so no intermediate concatenation is built.
    nonisolated public static func isLikelyGame(name: String, path: String?, bundleID: String?) -> Bool {
        if let path, pathHints.contains(where: { path.contains($0) }) { return true }

        let loweredName = name.lowercased()
        if knownNames.contains(where: { loweredName.contains($0) }) { return true }

        if let bundleID {
            let lowered = bundleID.lowercased()
            if lowered.contains("game") { return true }
            if knownNames.contains(where: { lowered.contains($0) }) { return true }
        }

        if let path {
            let lowered = path.lowercased()
            if knownNames.contains(where: { lowered.contains($0) }) { return true }
        }

        return false
    }
}

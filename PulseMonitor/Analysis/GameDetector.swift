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

    public func detect(in processes: [ProcessInfoModel]) async -> [ProcessInfoModel] {
        processes.filter { Self.isLikelyGame(name: $0.name, path: $0.executablePath, bundleID: $0.bundleIdentifier) }
    }

    public func analyzeGamePerformance(
        game: ProcessInfoModel,
        metrics: SystemMetrics,
        background: [ProcessInfoModel]
    ) -> BottleneckFinding {
        let bgCPU = background.filter { !$0.isGame && $0.cpuPercent > 10 }
        var recommendations: [String] = []
        var detail = ExplanationGenerator.gameSpecificAdvice(for: game.name)

        if metrics.cpu.totalUsage > 90 && metrics.gpu.utilization < 50 {
            detail += " Frame rate is likely CPU-limited."
            recommendations.append("Reduce simulation quality settings before graphics presets.")
        } else if metrics.gpu.utilization > 90 {
            detail += " Frame rate is likely GPU-limited."
            recommendations.append("Lower resolution, shadows, or anti-aliasing.")
        }
        if metrics.thermal.isThrottling {
            detail += " Thermal throttling is reducing clocks mid-session."
            recommendations.append("Improve cooling before increasing settings.")
        }
        if !bgCPU.isEmpty {
            recommendations.append("Quit background apps: \(bgCPU.prefix(3).map(\.name).joined(separator: ", ")).")
        }

        // Crude FPS estimation proxy from GPU/CPU headroom — not a true frame timer.
        let fpsEstimate = max(15, min(120, 120 - metrics.cpu.totalUsage * 0.4 - metrics.gpu.utilization * 0.3))
        detail += String(format: " Estimated smoothness proxy ~%.0f (not a true FPS counter).", fpsEstimate)

        return BottleneckFinding(
            id: UUID(),
            category: .game,
            severity: metrics.cpu.totalUsage > 90 || metrics.gpu.utilization > 90 ? .warning : .info,
            title: "Game Analysis: \(game.name)",
            summary: String(format: "%@ is active (CPU %.0f%%).", game.name, game.cpuPercent),
            detail: detail,
            relatedProcesses: [game.name] + bgCPU.prefix(3).map(\.name),
            recommendations: recommendations,
            detectedAt: .now,
            confidence: 0.7
        )
    }

    nonisolated public static func isLikelyGame(name: String, path: String?, bundleID: String?) -> Bool {
        if let path, pathHints.contains(where: { path.contains($0) }) { return true }

        var haystack = name.lowercased()
        if let bundleID {
            let lowered = bundleID.lowercased()
            if lowered.contains("game") { return true }
            haystack += " " + lowered
        }
        if let path { haystack += " " + path.lowercased() }

        return knownNames.contains { haystack.contains($0) }
    }
}

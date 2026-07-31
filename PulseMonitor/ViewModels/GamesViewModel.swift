import Foundation
import Observation

@MainActor
@Observable
public final class GamesViewModel {
    public let collector: MetricsCollector
    public let gameDetector: GameDetector
    public var findings: [BottleneckFinding] = []

    public init(collector: MetricsCollector, gameDetector: GameDetector) {
        self.collector = collector
        self.gameDetector = gameDetector
    }

    public var games: [ProcessInfoModel] { collector.detectedGames }

    public func refreshAnalysis() {
        guard let metrics = collector.latestMetrics else { return }
        Task {
            var result: [BottleneckFinding] = []
            for game in games {
                let finding = await gameDetector.analyzeGamePerformance(
                    game: game,
                    metrics: metrics,
                    background: collector.latestProcesses
                )
                result.append(finding)
            }
            findings = result
        }
    }
}

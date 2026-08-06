import Foundation

/// Performance Intelligence Engine (PIE) — Athena core facade.
/// Every module is independently callable; this type orchestrates a single snapshot.
public struct PerformanceIntelligenceEngine: Sendable {
    public let insights = PIEInsightModule()
    public let predictions = PIEPredictionModule()
    public let patterns = PIEPatternModule()
    public let recommendations = PIERecommendationModule()
    public let timeline = PIETimelineModule()
    public let optimization = PIEOptimizationModule()
    public let naturalLanguage = PIENaturalLanguageModule()
    public let learning = PIELearningModule()
    public let reports = PIEReportModule()
    public let knowledge = PIEKnowledgeModule()
    public let workloads = PIEWorkloadDetector()

    public init() {}

    public func evaluate(
        metrics: SystemMetrics,
        previous: SystemMetrics?,
        processes: [ProcessInfoModel],
        findings: [BottleneckFinding],
        games: [ProcessInfoModel],
        samples: [SystemMetrics],
        healthOverall: Double?,
        question: String?,
        learningEnabled: Bool,
        confidenceThreshold: Double,
        developerMode: Bool,
        predictionFrequency: AppSettings.AIPredictionFrequency = .normal,
        insightDetail: AppSettings.AIInsightDetail = .standard
    ) -> PIESnapshot {
        let habits = learning.observe(
            metrics: metrics,
            processes: processes,
            games: games,
            learningEnabled: learningEnabled
        )

        let insightLimit: Int = {
            switch insightDetail {
            case .concise: 4
            case .standard: 8
            case .detailed: 14
            }
        }()

        let horizons: [PredictionHorizon] = {
            switch predictionFrequency {
            case .low: [.minutes15, .minutes60]
            case .normal: PredictionHorizon.allCases
            case .high: PredictionHorizon.allCases
            }
        }()

        let live = Array(insights.liveInsights(
            metrics: metrics,
            processes: processes,
            findings: findings,
            games: games
        ).filter { $0.confidence >= confidenceThreshold }.prefix(insightLimit))

        let preds = predictions.predict(samples: samples, metrics: metrics, horizons: horizons)
            .filter { $0.confidence >= confidenceThreshold }

        let anomalies = patterns.anomalies(samples: samples, processes: processes, habits: habits)
            .filter { $0.confidence >= confidenceThreshold }

        let workload = workloads.detect(processes: processes, games: games, metrics: metrics)
        let suggestions = recommendations.recommend(
            metrics: metrics,
            processes: processes,
            insights: live,
            workload: workload
        ).filter { $0.confidence >= confidenceThreshold }

        let scorecard = optimization.scorecard(
            health: healthOverall ?? 100,
            suggestions: suggestions,
            anomalies: anomalies
        )

        let events = timeline.explain(previous: previous, current: metrics, processes: processes)
        let briefing = reports.dailyBriefing(
            samples: samples,
            processes: processes,
            health: healthOverall,
            suggestions: suggestions
        )

        let nl: ConfidenceFinding? = {
            guard let question, !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return naturalLanguage.answer(
                question: question,
                metrics: metrics,
                processes: processes,
                samples: samples,
                findings: findings,
                timeline: events,
                health: healthOverall
            )
        }()

        var trace: [String] = []
        if developerMode {
            trace.append("samples=\(samples.count)")
            trace.append("habits.sampleCount=\(habits.sampleCount)")
            trace.append("insights=\(live.count) preds=\(preds.count) anomalies=\(anomalies.count)")
            trace.append("workload=\(workload.kind.rawValue) conf=\(Int(workload.confidence))")
            trace.append("threshold=\(Int(confidenceThreshold))")
            if let b = insights.primaryBottleneck(from: live, findings: findings) {
                trace.append("bottleneck=\(b.title) conf=\(Int(b.confidence))")
            }
        }

        return PIESnapshot(
            timestamp: metrics.timestamp,
            mood: mood(metrics: metrics, health: healthOverall),
            overallHealth: healthOverall ?? 100,
            optimizationScore: scorecard.score,
            currentBottleneck: insights.primaryBottleneck(from: live, findings: findings),
            predictedBottleneck: predictions.predictedBottleneck(from: preds),
            insights: live,
            predictions: Array(preds.prefix(12)),
            anomalies: anomalies,
            suggestions: suggestions,
            timeline: events,
            workload: workload,
            briefing: briefing,
            nlAnswer: nl,
            developerTrace: trace
        )
    }

    public func mood(metrics: SystemMetrics, health: Double?) -> SystemMood {
        if metrics.thermal.thermalState == .critical || metrics.thermal.isThrottling {
            return .criticalCooling
        }
        if let t = metrics.thermal.cpuTemperatureC, t >= 95 {
            return .criticalCooling
        }
        if metrics.thermal.thermalState == .serious || (metrics.thermal.cpuTemperatureC ?? 0) >= 88 {
            return .thermalStress
        }
        if metrics.memory.pressure == .critical || metrics.memory.usagePercent >= 92 {
            return .memoryPressure
        }
        if let root = metrics.storage.volumes.first(where: \.isRoot), root.usedPercent >= 92 {
            return .storagePressure
        }
        if metrics.battery.isPresent, let h = metrics.battery.healthPercent, h < 80 {
            return .batteryConcern
        }
        if metrics.cpu.totalUsage >= 75 || (metrics.gpu.utilization ?? 0) >= 85 {
            return .heavyLoad
        }
        if metrics.cpu.totalUsage < 15, metrics.memory.usagePercent < 55 {
            return .idleQuiet
        }
        if let health, health >= 85 { return .excellent }
        return .excellent
    }
}

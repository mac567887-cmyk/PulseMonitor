import Foundation
import Observation

/// Version 5 Athena session — owns PIE snapshots and AI Copilot state.
@MainActor
@Observable
public final class AthenaSession {
    public private(set) var snapshot: PIESnapshot?
    public private(set) var timelineLog: [TimelineIntelEvent] = []
    public private(set) var habits: PIEHabitProfile = .empty
    public var question: String = ""
    public var selectedKnowledgeTopic: String = "cpu"
    public private(set) var knowledgeArticle: KnowledgeArticle?
    public private(set) var lastVoice: VoiceCommandResult?

    public let engine = PerformanceIntelligenceEngine()
    private var previousMetrics: SystemMetrics?
    private var lastProcesses: [ProcessInfoModel] = []
    private var lastFindings: [BottleneckFinding] = []
    private var lastSamples: [SystemMetrics] = []

    public init() {
        habits = engine.learning.load()
    }

    public func tick(
        metrics: SystemMetrics,
        processes: [ProcessInfoModel],
        findings: [BottleneckFinding],
        games: [ProcessInfoModel],
        samples: [SystemMetrics],
        healthOverall: Double?,
        settings: AppSettings
    ) {
        lastProcesses = processes
        lastFindings = findings
        lastSamples = samples

        let snap = engine.evaluate(
            metrics: metrics,
            previous: previousMetrics,
            processes: processes,
            findings: findings,
            games: games,
            samples: samples,
            healthOverall: healthOverall,
            question: question.isEmpty ? nil : question,
            learningEnabled: settings.aiLearningEnabled,
            confidenceThreshold: settings.aiConfidenceThreshold,
            developerMode: settings.developerModeEnabled || settings.aiDeveloperReasoning,
            predictionFrequency: settings.aiPredictionFrequency,
            insightDetail: settings.aiInsightDetail
        )
        snapshot = snap
        if !snap.timeline.isEmpty {
            timelineLog.append(contentsOf: snap.timeline)
            if timelineLog.count > 200 {
                timelineLog.removeFirst(timelineLog.count - 200)
            }
        }
        habits = engine.learning.load()
        knowledgeArticle = engine.knowledge.article(for: selectedKnowledgeTopic, metrics: metrics)
        previousMetrics = metrics
    }

    public func ask() {
        guard let metrics = previousMetrics else { return }
        let answer = engine.naturalLanguage.answer(
            question: question,
            metrics: metrics,
            processes: lastProcesses,
            samples: lastSamples,
            findings: lastFindings,
            timeline: timelineLog,
            health: snapshot?.overallHealth
        )
        guard let snap = snapshot else {
            snapshot = PIESnapshot(
                timestamp: .now,
                mood: .excellent,
                overallHealth: 100,
                optimizationScore: 100,
                currentBottleneck: nil,
                predictedBottleneck: nil,
                insights: [],
                predictions: [],
                anomalies: [],
                suggestions: [],
                timeline: [],
                workload: .init(kind: .unknown, confidence: 0, evidence: [], advice: []),
                briefing: nil,
                nlAnswer: answer,
                developerTrace: []
            )
            return
        }
        snapshot = PIESnapshot(
            timestamp: snap.timestamp,
            mood: snap.mood,
            overallHealth: snap.overallHealth,
            optimizationScore: snap.optimizationScore,
            currentBottleneck: snap.currentBottleneck,
            predictedBottleneck: snap.predictedBottleneck,
            insights: snap.insights,
            predictions: snap.predictions,
            anomalies: snap.anomalies,
            suggestions: snap.suggestions,
            timeline: snap.timeline,
            workload: snap.workload,
            briefing: snap.briefing,
            nlAnswer: answer,
            developerTrace: snap.developerTrace
        )
    }

    public func handleVoice(_ utterance: String) {
        lastVoice = VoiceIntentRouter.parse(utterance)
        if lastVoice?.intent == .dailyReport || lastVoice?.intent == .systemStatus || lastVoice?.intent == .whyFanLoud {
            question = utterance
            ask()
        }
    }

    public func refreshKnowledge(metrics: SystemMetrics?) {
        guard let metrics else { return }
        knowledgeArticle = engine.knowledge.article(for: selectedKnowledgeTopic, metrics: metrics)
    }
}

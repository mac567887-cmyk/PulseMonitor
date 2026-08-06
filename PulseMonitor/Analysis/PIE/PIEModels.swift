import Foundation

// MARK: - Shared PIE contracts (Version 5 — Athena)

public enum SystemMood: String, Sendable, Codable, CaseIterable, Identifiable {
    case excellent
    case heavyLoad
    case thermalStress
    case criticalCooling
    case memoryPressure
    case storagePressure
    case batteryConcern
    case idleQuiet

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .excellent: "Excellent"
        case .heavyLoad: "Under Heavy Load"
        case .thermalStress: "Thermal Stress"
        case .criticalCooling: "Critical Cooling Required"
        case .memoryPressure: "Memory Pressure"
        case .storagePressure: "Storage Pressure"
        case .batteryConcern: "Battery Concern"
        case .idleQuiet: "Quiet / Idle"
        }
    }

    public var symbol: String {
        switch self {
        case .excellent, .idleQuiet: "🟢"
        case .heavyLoad: "🟡"
        case .thermalStress, .memoryPressure, .storagePressure, .batteryConcern: "🟠"
        case .criticalCooling: "🔴"
        }
    }
}

public struct ConfidenceFinding: Sendable, Codable, Equatable, Identifiable {
    public var id: UUID
    public let title: String
    public let summary: String
    public let why: String
    public let confidence: Double
    public let category: String
    public let evidence: [String]
    public let recommendations: [String]
    public let isEstimate: Bool

    public init(
        id: UUID = UUID(),
        title: String,
        summary: String,
        why: String,
        confidence: Double,
        category: String,
        evidence: [String] = [],
        recommendations: [String] = [],
        isEstimate: Bool = false
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.why = why
        self.confidence = min(100, max(0, confidence))
        self.category = category
        self.evidence = evidence
        self.recommendations = recommendations
        self.isEstimate = isEstimate
    }
}

public enum PredictionHorizon: Int, Sendable, Codable, CaseIterable, Identifiable {
    case minutes5 = 5
    case minutes15 = 15
    case minutes30 = 30
    case minutes60 = 60

    public var id: Int { rawValue }
    public var label: String { "\(rawValue) min" }
}

public struct PIEPrediction: Sendable, Codable, Equatable, Identifiable {
    public var id: UUID
    public let kind: Kind
    public let horizon: PredictionHorizon
    public let summary: String
    public let confidence: Double
    public let projectedValue: Double?
    public let unit: String?
    public let isEstimate: Bool
    public let evidence: [String]

    public enum Kind: String, Sendable, Codable {
        case thermalThrottle
        case batteryDepletion
        case memoryExhaustion
        case storageSaturation
        case networkCongestion
        case fanSpeed
        case temperature
        case batteryRuntime
        case swapUsage
        case futureBottleneck
    }

    public init(
        id: UUID = UUID(),
        kind: Kind,
        horizon: PredictionHorizon,
        summary: String,
        confidence: Double,
        projectedValue: Double? = nil,
        unit: String? = nil,
        isEstimate: Bool = true,
        evidence: [String] = []
    ) {
        self.id = id
        self.kind = kind
        self.horizon = horizon
        self.summary = summary
        self.confidence = min(100, max(0, confidence))
        self.projectedValue = projectedValue
        self.unit = unit
        self.isEstimate = isEstimate
        self.evidence = evidence
    }
}

public struct TimelineIntelEvent: Sendable, Codable, Equatable, Identifiable {
    public var id: UUID
    public let timestamp: Date
    public let title: String
    public let reason: String
    public let category: String
    public let confidence: Double

    public init(
        id: UUID = UUID(),
        timestamp: Date,
        title: String,
        reason: String,
        category: String,
        confidence: Double
    ) {
        self.id = id
        self.timestamp = timestamp
        self.title = title
        self.reason = reason
        self.category = category
        self.confidence = confidence
    }
}

public enum WorkloadKind: String, Sendable, Codable, CaseIterable {
    case gaming, programming, videoEditing, streaming, virtualMachine
    case rendering, browsing, office, machineLearning, unknown

    public var displayName: String {
        switch self {
        case .gaming: "Gaming"
        case .programming: "Programming"
        case .videoEditing: "Video Editing"
        case .streaming: "Streaming"
        case .virtualMachine: "Virtual Machine"
        case .rendering: "Rendering"
        case .browsing: "Browsing"
        case .office: "Office Work"
        case .machineLearning: "Machine Learning"
        case .unknown: "General"
        }
    }
}

public struct WorkloadDetection: Sendable, Codable, Equatable {
    public let kind: WorkloadKind
    public let confidence: Double
    public let evidence: [String]
    public let advice: [String]
}

public struct OptimizationScorecard: Sendable, Codable, Equatable {
    public let score: Double
    public let summary: String
    public let suggestions: [ConfidenceFinding]
}

public struct DailyBriefing: Sendable, Codable, Equatable {
    public let generatedAt: Date
    public let greeting: String
    public let narrative: String
    public let highlights: [String]
    public let recommendations: [String]
    public let peakCPU: Double?
    public let peakTemperatureC: Double?
    public let topApp: String?
}

public struct KnowledgeArticle: Sendable, Codable, Equatable, Identifiable {
    public var id: String { topic }
    public let topic: String
    public let definition: String
    public let healthyRange: String
    public let currentStatus: String
    public let importance: String
    public let commonProblems: [String]
    public let tips: [String]
}

public struct PIESnapshot: Sendable, Codable, Equatable {
    public let timestamp: Date
    public let mood: SystemMood
    public let overallHealth: Double
    public let optimizationScore: Double
    public let currentBottleneck: ConfidenceFinding?
    public let predictedBottleneck: PIEPrediction?
    public let insights: [ConfidenceFinding]
    public let predictions: [PIEPrediction]
    public let anomalies: [ConfidenceFinding]
    public let suggestions: [ConfidenceFinding]
    public let timeline: [TimelineIntelEvent]
    public let workload: WorkloadDetection
    public let briefing: DailyBriefing?
    public let nlAnswer: ConfidenceFinding?
    public let developerTrace: [String]
}

public enum VoiceIntent: String, Sendable, Codable {
    case systemStatus
    case whyFanLoud
    case runBenchmark
    case openGaming
    case dailyReport
    case unknown
}

public struct VoiceCommandResult: Sendable, Codable, Equatable {
    public let intent: VoiceIntent
    public let spokenReply: String
    public let confidence: Double
    public let navigationHint: String?
}

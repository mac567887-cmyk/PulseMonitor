import Foundation

/// A diagnosed performance bottleneck with plain-English explanation.
public struct BottleneckFinding: Sendable, Codable, Identifiable, Equatable {
    public let id: UUID
    public let category: Category
    public let severity: Severity
    public let title: String
    public let summary: String
    public let detail: String
    public let relatedProcesses: [String]
    public let recommendations: [String]
    public let detectedAt: Date
    public let confidence: Double

    public enum Category: String, Sendable, Codable, Equatable, CaseIterable {
        case cpu
        case gpu
        case memory
        case thermal
        case storage
        case network
        case battery
        case game
        case system
    }

    public enum Severity: String, Sendable, Codable, Equatable, Comparable {
        case info
        case warning
        case critical

        public static func < (lhs: Severity, rhs: Severity) -> Bool {
            lhs.rank < rhs.rank
        }

        private var rank: Int {
            switch self {
            case .info: 0
            case .warning: 1
            case .critical: 2
            }
        }
    }
}

/// Result of a full analysis pass.
public struct AnalysisReport: Sendable, Codable, Equatable {
    public let timestamp: Date
    public let findings: [BottleneckFinding]
    public let primaryBottleneck: BottleneckFinding?
    public let overallHealthScore: Double
    public let narrative: String
}

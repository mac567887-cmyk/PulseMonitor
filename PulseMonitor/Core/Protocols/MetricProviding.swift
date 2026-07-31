import Foundation

/// Protocol for asynchronous metric collection services.
public protocol MetricProviding<Metric>: Actor {
    associatedtype Metric: Sendable
    /// Collects the latest metric sample.
    func sample() async -> Metric
}

/// Protocol for services that expose historical samples.
public protocol HistoryProviding: Actor {
    associatedtype Sample: Sendable
    func recent(limit: Int) async -> [Sample]
}

/// Retention window for historical metric storage.
public enum HistoryRetention: String, Sendable, Codable, CaseIterable, Identifiable {
    case fifteenMinutes = "15m"
    case oneHour = "1h"
    case sixHours = "6h"
    case twentyFourHours = "24h"
    case sevenDays = "7d"
    case thirtyDays = "30d"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .fifteenMinutes: "15 Minutes"
        case .oneHour: "1 Hour"
        case .sixHours: "6 Hours"
        case .twentyFourHours: "24 Hours"
        case .sevenDays: "7 Days"
        case .thirtyDays: "30 Days"
        }
    }

    public var seconds: TimeInterval {
        switch self {
        case .fifteenMinutes: 15 * 60
        case .oneHour: 60 * 60
        case .sixHours: 6 * 60 * 60
        case .twentyFourHours: 24 * 60 * 60
        case .sevenDays: 7 * 24 * 60 * 60
        case .thirtyDays: 30 * 24 * 60 * 60
        }
    }
}

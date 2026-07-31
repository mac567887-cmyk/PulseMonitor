import Foundation

/// Computes simple trends and linear predictions over recent samples.
public enum TrendCalculator {
    public enum Trend: String, Sendable, Equatable {
        case rising
        case falling
        case stable

        public var symbol: String {
            switch self {
            case .rising: "↗"
            case .falling: "↘"
            case .stable: "→"
            }
        }
    }

    public static func trend(of values: [Double], threshold: Double = 0.05) -> Trend {
        guard values.count >= 3 else { return .stable }
        let recent = Array(values.suffix(min(12, values.count)))
        let firstHalf = Array(recent.prefix(recent.count / 2))
        let secondHalf = Array(recent.suffix(recent.count / 2))
        let a = average(firstHalf)
        let b = average(secondHalf)
        guard a != 0 else { return b > threshold ? .rising : .stable }
        let delta = (b - a) / max(abs(a), 0.001)
        if delta > threshold { return .rising }
        if delta < -threshold { return .falling }
        return .stable
    }

    /// Predicts the next value using a simple linear regression over the window.
    public static func predictNext(of values: [Double]) -> Double? {
        guard values.count >= 3 else { return values.last }
        let n = Double(values.count)
        var sumX = 0.0, sumY = 0.0, sumXY = 0.0, sumXX = 0.0
        for (i, y) in values.enumerated() {
            let x = Double(i)
            sumX += x
            sumY += y
            sumXY += x * y
            sumXX += x * x
        }
        let denominator = n * sumXX - sumX * sumX
        guard abs(denominator) > 1e-9 else { return values.last }
        let slope = (n * sumXY - sumX * sumY) / denominator
        let intercept = (sumY - slope * sumX) / n
        return intercept + slope * n
    }

    private static func average(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }
}

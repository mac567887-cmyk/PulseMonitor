import SwiftUI
import Charts

/// Live dashboard card with value, trend, mini-graph, status, and prediction.
public struct MetricCard: View {
    public let title: String
    public let valueText: String
    public let subtitle: String
    public let history: [Double]
    public let trend: TrendCalculator.Trend
    public let status: MetricStatus
    public let predictionText: String?
    public let accent: Color

    public init(
        title: String,
        valueText: String,
        subtitle: String,
        history: [Double],
        trend: TrendCalculator.Trend,
        status: MetricStatus,
        predictionText: String? = nil,
        accent: Color = Color.accentColor
    ) {
        self.title = title
        self.valueText = valueText
        self.subtitle = subtitle
        self.history = history
        self.trend = trend
        self.status = status
        self.predictionText = predictionText
        self.accent = accent
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.6)
                Spacer()
                StatusPill(status: status)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(valueText)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                Text(trend.symbol)
                    .foregroundStyle(trendColor)
                    .font(.title3.weight(.bold))
            }

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            MiniSparkline(values: history, accent: accent)
                .frame(height: 36)

            if let predictionText {
                Text(predictionText)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                )
        )
    }

    private var trendColor: Color {
        switch trend {
        case .rising: .orange
        case .falling: .green
        case .stable: .secondary
        }
    }
}

public struct StatusPill: View {
    public let status: MetricStatus
    public var body: some View {
        Text(status.label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private var color: Color {
        switch status {
        case .ok: .green
        case .warning: .orange
        case .critical: .red
        }
    }
}

public struct MiniSparkline: View {
    public let values: [Double]
    public let accent: Color

    public var body: some View {
        Chart {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                LineMark(
                    x: .value("t", index),
                    y: .value("v", value)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(accent)

                AreaMark(
                    x: .value("t", index),
                    y: .value("v", value)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(accent.opacity(0.15))
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
    }
}

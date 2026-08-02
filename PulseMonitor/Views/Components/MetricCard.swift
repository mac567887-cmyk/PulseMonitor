import SwiftUI

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

/// Compact trend line for dashboard cards.
///
/// Deliberately drawn with `Canvas` rather than `Chart`. The dashboard shows
/// fifteen of these at once and each tick invalidates all of them; profiling the
/// running app showed Swift Charts rebuilding its scales and plot layout for
/// every card, which accounted for roughly half of all main-thread time. The
/// module views keep Swift Charts, where axes, selection and tooltips earn it.
public struct MiniSparkline: View {
    public let values: [Double]
    public let accent: Color

    public init(values: [Double], accent: Color) {
        self.values = values
        self.accent = accent
    }

    public var body: some View {
        Canvas(rendersAsynchronously: false) { context, size in
            guard values.count > 1 else { return }
            let points = Self.layout(values: values, in: size)
            let line = Self.smoothPath(through: points)

            var fill = line
            fill.addLine(to: CGPoint(x: points[points.count - 1].x, y: size.height))
            fill.addLine(to: CGPoint(x: points[0].x, y: size.height))
            fill.closeSubpath()

            context.fill(
                fill,
                with: .linearGradient(
                    Gradient(colors: [accent.opacity(0.28), accent.opacity(0.02)]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: 0, y: size.height)
                )
            )
            context.stroke(
                line,
                with: .color(accent),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
            )
        }
        .accessibilityHidden(true)
    }

    /// Maps samples into the canvas, scaling to the window's own range so small
    /// fluctuations stay visible. A flat series is drawn through the middle.
    private static func layout(values: [Double], in size: CGSize) -> [CGPoint] {
        let lowest = values.min() ?? 0
        let highest = values.max() ?? 0
        let span = highest - lowest
        let inset: CGFloat = 1.5
        let usableHeight = max(size.height - inset * 2, 1)
        let stride = size.width / CGFloat(values.count - 1)

        return values.enumerated().map { index, value in
            let normalized = span > 0 ? (value - lowest) / span : 0.5
            return CGPoint(
                x: CGFloat(index) * stride,
                y: inset + usableHeight * (1 - normalized)
            )
        }
    }

    /// Centripetal-style Catmull-Rom spline expressed as cubic Béziers, matching
    /// the curve shape Swift Charts produced before.
    private static func smoothPath(through points: [CGPoint]) -> Path {
        var path = Path()
        path.move(to: points[0])
        guard points.count > 2 else {
            path.addLine(to: points[1])
            return path
        }

        for index in 0..<(points.count - 1) {
            let p0 = points[max(index - 1, 0)]
            let p1 = points[index]
            let p2 = points[index + 1]
            let p3 = points[min(index + 2, points.count - 1)]

            let control1 = CGPoint(
                x: p1.x + (p2.x - p0.x) / 6,
                y: p1.y + (p2.y - p0.y) / 6
            )
            let control2 = CGPoint(
                x: p2.x - (p3.x - p1.x) / 6,
                y: p2.y - (p3.y - p1.y) / 6
            )
            path.addCurve(to: p2, control1: control1, control2: control2)
        }
        return path
    }
}

import SwiftUI

/// Visual heat map of per-core CPU utilization.
public struct CoreHeatmapView: View {
    public let values: [Double]
    public let columns: Int

    public init(values: [Double], columns: Int = 4) {
        self.values = values
        self.columns = max(1, columns)
    }

    public var body: some View {
        let rows = stride(from: 0, to: values.count, by: columns).map { start in
            Array(values[start..<min(start + columns, values.count)])
        }
        VStack(spacing: 6) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 6) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, value in
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(color(for: value))
                            .frame(height: 28)
                            .overlay(
                                Text(String(format: "%.0f", value))
                                    .font(.caption2.monospacedDigit().weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.9))
                            )
                    }
                }
            }
        }
    }

    private func color(for value: Double) -> Color {
        switch value {
        case ..<30: Color.blue.opacity(0.55)
        case ..<60: Color.cyan.opacity(0.7)
        case ..<85: Color.orange.opacity(0.8)
        default: Color.red.opacity(0.85)
        }
    }
}

import SwiftUI
import Charts

public struct HistoryView: View {
    @Bindable var viewModel: HistoryViewModel

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                SectionHeader("Historical Timeline", subtitle: "Scroll backwards through recorded metrics")
                Spacer()
                Picker("Retention", selection: $viewModel.selectedRetention) {
                    ForEach(HistoryRetention.allCases) { r in
                        Text(r.displayName).tag(r)
                    }
                }
                .frame(width: 160)
                Button("Reload") { viewModel.reload() }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)

            Chart(viewModel.points) { point in
                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("CPU", point.cpu)
                )
                .foregroundStyle(by: .value("Metric", "CPU"))
                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Memory", point.memory)
                )
                .foregroundStyle(by: .value("Metric", "Memory"))
                if let gpu = point.gpu {
                    LineMark(
                        x: .value("Time", point.timestamp),
                        y: .value("GPU", gpu)
                    )
                    .foregroundStyle(by: .value("Metric", "GPU"))
                }
            }
            .chartYScale(domain: 0...100)
            .padding(24)
            .frame(maxHeight: .infinity)
        }
        .background(AmbientBackground())
        .onAppear { viewModel.reload() }
        .onChange(of: viewModel.selectedRetention) { _, _ in viewModel.reload() }
    }
}

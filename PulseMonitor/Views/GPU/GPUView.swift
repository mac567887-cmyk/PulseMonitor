import SwiftUI
import Charts

public struct GPUView: View {
    @Bindable var viewModel: GPUViewModel

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SectionHeader("GPU", subtitle: viewModel.metrics?.deviceName)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160))], spacing: 12) {
                    tile("Utilization", Formatters.percent(viewModel.metrics?.utilization ?? 0))
                    tile("Renderer", Formatters.percent(viewModel.metrics?.rendererUtilization ?? 0))
                    tile("Tiler", Formatters.percent(viewModel.metrics?.tilerUtilization ?? 0))
                    tile("Metal", viewModel.metrics?.isMetalActive == true ? "Active" : "Idle")
                    tile("Memory", Formatters.bytes(viewModel.metrics?.memoryTotalBytes ?? 0))
                    tile("WindowServer", Formatters.percent(viewModel.metrics?.windowServerCPU ?? 0))
                }
                Chart {
                    ForEach(Array(viewModel.history.enumerated()), id: \.offset) { i, v in
                        LineMark(x: .value("t", i), y: .value("gpu", v))
                    }
                }
                .frame(height: 200)
                .chartYScale(domain: 0...100)
            }
            .padding(24)
        }
        .background(AmbientBackground())
    }

    private func tile(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.weight(.semibold))
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

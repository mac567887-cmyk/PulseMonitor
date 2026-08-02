import SwiftUI
import Charts

public struct GPUView: View {
    @Bindable var viewModel: GPUViewModel

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SectionHeader("GPU", subtitle: viewModel.metrics?.deviceName)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160))], spacing: 12) {
                    tile("Utilization", Formatters.percent(viewModel.metrics?.utilization))
                    tile("Renderer", Formatters.percent(viewModel.metrics?.rendererUtilization))
                    tile("Tiler", Formatters.percent(viewModel.metrics?.tilerUtilization))
                    tile("Core Clock", Formatters.mhz(viewModel.metrics?.frequencyMHz))
                    tile("Temperature", Formatters.celsius(viewModel.metrics?.temperatureC))
                    tile("Power", Formatters.watts(viewModel.metrics?.powerWatts))
                    tile("VRAM In Use", viewModel.metrics?.memoryUsedBytes.map(Formatters.bytes) ?? "—")
                    tile("VRAM Total", viewModel.metrics?.memoryTotalBytes.map(Formatters.bytes) ?? "—")
                }

                if viewModel.metrics?.hasUtilizationCounters == false {
                    CapabilityNotice(
                        state: .unsupported(
                            reason: "\(viewModel.metrics?.deviceName ?? "This GPU")'s driver does not publish utilization counters, and the IOReport channels Activity Monitor reads are private."
                        )
                    )
                } else {
                    Chart {
                        ForEach(Array(viewModel.history.enumerated()), id: \.offset) { i, v in
                            LineMark(x: .value("t", i), y: .value("gpu", v))
                        }
                    }
                    .frame(height: 200)
                    .chartYScale(domain: 0...100)
                }
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

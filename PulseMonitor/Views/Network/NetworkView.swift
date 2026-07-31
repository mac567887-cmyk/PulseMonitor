import SwiftUI
import Charts

public struct NetworkView: View {
    @Bindable var viewModel: NetworkViewModel

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SectionHeader("Network")
                HStack {
                    labeled("Download", Formatters.bytesPerSecond(viewModel.metrics?.bytesInPerSec ?? 0))
                    labeled("Upload", Formatters.bytesPerSecond(viewModel.metrics?.bytesOutPerSec ?? 0))
                    labeled("Latency", viewModel.metrics?.latencyMs.map { String(format: "%.0f ms", $0) } ?? "—")
                }
                Chart {
                    ForEach(Array(viewModel.inHistory.enumerated()), id: \.offset) { i, v in
                        LineMark(x: .value("t", i), y: .value("in", v))
                            .foregroundStyle(.cyan)
                    }
                    ForEach(Array(viewModel.outHistory.enumerated()), id: \.offset) { i, v in
                        LineMark(x: .value("t", i), y: .value("out", v))
                            .foregroundStyle(.orange)
                    }
                }
                .frame(height: 200)

                ForEach(viewModel.metrics?.interfaces ?? []) { iface in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(iface.displayName).font(.headline)
                            Text(iface.kind).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("↓ \(Formatters.bytesPerSecond(iface.bytesInPerSec))")
                        Text("↑ \(Formatters.bytesPerSecond(iface.bytesOutPerSec))")
                    }
                    .padding(10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .padding(24)
        }
        .background(AmbientBackground())
    }

    private func labeled(_ t: String, _ v: String) -> some View {
        VStack(alignment: .leading) {
            Text(t).font(.caption).foregroundStyle(.secondary)
            Text(v).font(.title3.weight(.semibold))
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

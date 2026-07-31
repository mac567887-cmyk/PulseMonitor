import SwiftUI
import Charts

public struct MemoryView: View {
    @Bindable var viewModel: MemoryViewModel

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SectionHeader("Memory", subtitle: "Pressure: \(viewModel.metrics?.pressure.displayName ?? "—")")
                if let m = viewModel.metrics {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: 12) {
                        tile("Physical", Formatters.bytes(m.totalBytes))
                        tile("Used", Formatters.bytes(m.usedBytes))
                        tile("Free", Formatters.bytes(m.freeBytes))
                        tile("App Memory", Formatters.bytes(m.appMemoryBytes))
                        tile("Wired", Formatters.bytes(m.wiredBytes))
                        tile("Compressed", Formatters.bytes(m.compressedBytes))
                        tile("Cached", Formatters.bytes(m.cachedBytes))
                        tile("Swap", Formatters.bytes(m.swapUsedBytes))
                    }
                }
                Chart {
                    ForEach(Array(viewModel.history.enumerated()), id: \.offset) { i, v in
                        LineMark(x: .value("t", i), y: .value("mem", v))
                            .foregroundStyle(.teal)
                    }
                }
                .frame(height: 180)
                .chartYScale(domain: 0...100)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Largest Consumers").font(.headline)
                    ForEach(viewModel.topConsumers) { proc in
                        HStack {
                            Text(proc.name)
                            Spacer()
                            Text(Formatters.bytes(proc.memoryBytes)).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .padding(24)
        }
        .background(AmbientBackground())
    }

    private func tile(_ t: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(t).font(.caption).foregroundStyle(.secondary)
            Text(v).font(.headline)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

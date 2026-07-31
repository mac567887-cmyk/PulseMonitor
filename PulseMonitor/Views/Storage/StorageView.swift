import SwiftUI

public struct StorageView: View {
    @Bindable var viewModel: StorageViewModel

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SectionHeader("Storage", subtitle: "SMART: \(viewModel.metrics?.smartHealth.displayName ?? "—")")
                HStack {
                    labeled("Read", Formatters.bytesPerSecond(viewModel.metrics?.readBytesPerSec ?? 0))
                    labeled("Write", Formatters.bytesPerSecond(viewModel.metrics?.writeBytesPerSec ?? 0))
                    labeled("Read Ops", String(format: "%.0f/s", viewModel.metrics?.readOpsPerSec ?? 0))
                    labeled("Write Ops", String(format: "%.0f/s", viewModel.metrics?.writeOpsPerSec ?? 0))
                }
                ForEach(viewModel.metrics?.volumes ?? []) { volume in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(volume.name).font(.headline)
                            if volume.isRoot { Text("Boot").font(.caption2).padding(4).background(.blue.opacity(0.2), in: Capsule()) }
                            Spacer()
                            Text("\(Formatters.bytes(volume.usedBytes)) / \(Formatters.bytes(volume.totalBytes))")
                                .foregroundStyle(.secondary)
                        }
                        ProgressView(value: volume.usedPercent, total: 100)
                        Text(volume.path).font(.caption).foregroundStyle(.tertiary)
                    }
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .padding(24)
        }
        .background(AmbientBackground())
    }

    private func labeled(_ t: String, _ v: String) -> some View {
        VStack(alignment: .leading) {
            Text(t).font(.caption).foregroundStyle(.secondary)
            Text(v).font(.headline)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

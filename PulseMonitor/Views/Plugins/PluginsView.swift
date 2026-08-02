import SwiftUI

/// Catalogue of built-in and disk-discovered plugins.
public struct PluginsView: View {
    @Bindable var host: PluginHost

    public init(host: PluginHost) {
        self.host = host
    }

    public var body: some View {
        List {
            Section {
                Text("Plugins can add widgets, sensors, exporters, themes and automation. Drop a `.pulsemonitorplugin` package into the Plugins folder to register it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Scan") { host.scan() }
                    Button("Open Plugins Folder") { host.openPluginsFolder() }
                }
                if let error = host.lastScanError {
                    Text(error).foregroundStyle(.red)
                }
            }

            Section("Installed") {
                if host.plugins.isEmpty {
                    Text("No plugins discovered yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(host.plugins) { plugin in
                        pluginRow(plugin)
                    }
                }
            }

            if !host.sensorReadings().isEmpty {
                Section("Active Sensors") {
                    ForEach(host.sensorReadings()) { reading in
                        LabeledContent(reading.label, value: reading.value)
                    }
                }
            }
        }
        .navigationTitle("Plugins")
        .onAppear { host.scan() }
    }

    @ViewBuilder
    private func pluginRow(_ plugin: PluginRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(plugin.manifest.name).font(.headline)
                    Text("\(plugin.manifest.author) · v\(plugin.manifest.version)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle(
                    "Enabled",
                    isOn: Binding(
                        get: { plugin.isEnabled },
                        set: { host.setEnabled(plugin.manifest.id, enabled: $0) }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
            }
            Text(plugin.manifest.summary)
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(plugin.manifest.capabilities) { capability in
                    Text(capability.displayName)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())
                }
                if plugin.isLoaded {
                    Label("Loaded", systemImage: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
            }
            if let error = plugin.loadError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
    }
}

import SwiftUI

/// Drag-and-drop custom dashboard built from resizable metric widgets.
public struct WidgetBoardView: View {
    @Bindable var store: WidgetBoardStore
    @Bindable var collector: MetricsCollector
    var pluginHost: PluginHost
    @Environment(\.theme) private var theme

    public init(store: WidgetBoardStore, collector: MetricsCollector, pluginHost: PluginHost) {
        self.store = store
        self.collector = collector
        self.pluginHost = pluginHost
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 220, maximum: 420), spacing: 14)],
                    spacing: 14
                ) {
                    ForEach(store.placements) { placement in
                        widgetCard(placement)
                    }
                }
                .padding(20)
            }
        }
        .background(AmbientBackdrop())
        .navigationTitle("Widgets")
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("Custom Dashboard")
                .font(.title2.weight(.semibold))
            Spacer()
            if store.isEditing {
                Menu("Add Widget") {
                    ForEach(WidgetKind.allCases) { kind in
                        Button {
                            store.add(kind)
                        } label: {
                            Label(kind.title, systemImage: kind.symbol)
                        }
                    }
                }
                Button("Reset") { store.reset() }
                Button("Done") { store.isEditing = false }
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Edit") { store.isEditing = true }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private func widgetCard(_ placement: WidgetPlacement) -> some View {
        let metrics = collector.latestMetrics
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(placement.kind.title, systemImage: placement.kind.symbol)
                    .font(.headline)
                Spacer()
                if store.isEditing {
                    Menu {
                        ForEach(WidgetSize.allCases) { size in
                            Button(size.displayName) { store.resize(placement.id, to: size) }
                        }
                        Divider()
                        Button("Remove", role: .destructive) { store.remove(placement.id) }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                }
            }
            widgetBody(placement.kind, metrics: metrics)
                .frame(minHeight: height(for: placement.size))
        }
        .glassCard(isElevated: store.isEditing)
        .opacity(store.isEditing ? 0.96 : 1)
    }

    private func height(for size: WidgetSize) -> CGFloat {
        switch size {
        case .small: 96
        case .medium: 140
        case .large: 200
        }
    }

    @ViewBuilder
    private func widgetBody(_ kind: WidgetKind, metrics: SystemMetrics?) -> some View {
        switch kind {
        case .cpuGauge:
            PulseGauge(
                value: (metrics?.cpu.totalUsage ?? 0) / 100,
                label: Formatters.percent(metrics?.cpu.totalUsage ?? 0),
                caption: "CPU",
                tint: theme.accent
            )
            .frame(width: 120, height: 90)
        case .gpuGraph:
            sparkline(
                values: collector.gpuHistory,
                caption: Formatters.percent(metrics?.gpu.utilization)
            )
        case .ramGraph:
            sparkline(
                values: collector.memoryHistory,
                caption: Formatters.percent(metrics?.memory.usagePercent ?? 0)
            )
        case .thermals:
            VStack(alignment: .leading, spacing: 6) {
                metricRow("CPU", Formatters.celsius(metrics?.thermal.cpuTemperatureC))
                metricRow("GPU", Formatters.celsius(metrics?.thermal.gpuTemperatureC))
                metricRow("Battery", Formatters.celsius(metrics?.thermal.batteryTemperatureC))
                Text(metrics?.thermal.thermalState.displayName ?? "—")
                    .foregroundStyle(.secondary)
            }
        case .diskSpeed:
            VStack(alignment: .leading, spacing: 6) {
                metricRow("Read", Formatters.bytesPerSecond(metrics?.storage.readBytesPerSec ?? 0))
                metricRow("Write", Formatters.bytesPerSecond(metrics?.storage.writeBytesPerSec ?? 0))
            }
        case .clock:
            SwiftUI.TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(context.date, format: .dateTime.hour().minute().second())
                    .font(.system(size: 36, weight: .medium, design: .rounded))
                    .monospacedDigit()
            }
        case .calendar:
            VStack(alignment: .leading, spacing: 4) {
                Text(Date.now, format: .dateTime.weekday(.wide))
                    .foregroundStyle(theme.accent)
                Text(Date.now, format: .dateTime.month().day().year())
                    .font(.title3.weight(.semibold))
            }
        case .battery:
            VStack(alignment: .leading, spacing: 6) {
                metricRow("Charge", Formatters.percent(metrics?.battery.chargePercent))
                metricRow("Health", Formatters.percent(metrics?.battery.healthPercent))
                Text(metrics?.battery.isCharging == true ? "Charging" : "On battery / AC")
                    .foregroundStyle(.secondary)
            }
        case .fanRPM:
            let fans = metrics?.thermal.fanSpeedsRPM ?? []
            if fans.isEmpty {
                Text("No fan sensors published")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(fans) { fan in
                    metricRow(fan.name, Formatters.rpm(fan.rpm))
                }
            }
        case .network:
            VStack(alignment: .leading, spacing: 6) {
                metricRow("Down", Formatters.bytesPerSecond(metrics?.network.bytesInPerSec ?? 0))
                metricRow("Up", Formatters.bytesPerSecond(metrics?.network.bytesOutPerSec ?? 0))
            }
        case .pluginSensors:
            let readings = pluginHost.sensorReadings()
            if readings.isEmpty {
                Text("No plugin sensors active")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(readings.prefix(6)) { reading in
                    metricRow(reading.label, reading.value)
                }
            }
        }
    }

    private func metricRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.callout)
    }

    private func sparkline(values: [Double], caption: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(caption)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
            MiniSparkline(values: values, accent: theme.accent)
                .frame(height: 48)
        }
    }
}

import SwiftUI

/// Developer console, shown on the Dashboard when Developer Mode is on.
///
/// Exposes the raw values behind the polished readouts: every SMC key that
/// responded, how long the last sample took, and the capability decisions that
/// gate each control. Useful for verifying that a number on screen traces back
/// to a real sensor.
public struct DeveloperConsole: View {
    let collector: MetricsCollector
    @Bindable var controlCenter: ControlCenterViewModel

    @State private var tab: Tab = .sensors

    private enum Tab: String, CaseIterable, Identifiable {
        case sensors, capabilities, sampling
        var id: String { rawValue }
        var title: String {
            switch self {
            case .sensors: "Sensors"
            case .capabilities: "Capabilities"
            case .sampling: "Sampling"
            }
        }
    }

    public init(collector: MetricsCollector, controlCenter: ControlCenterViewModel) {
        self.collector = collector
        self.controlCenter = controlCenter
    }

    public var body: some View {
        GlassSection(title: "Developer Console", systemImage: "terminal") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases) { candidate in
                        Text(candidate.title).tag(candidate)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        switch tab {
                        case .sensors: sensorLines
                        case .capabilities: capabilityLines
                        case .sampling: samplingLines
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 190)
                .padding(9)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.black.opacity(0.35))
                )
            }
        } accessory: {
            Text(controlCenter.host.isAppleSilicon ? "arm64" : "x86_64")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .task {
            await controlCenter.load()
            controlCenter.startSensorPolling()
        }
        .onDisappear { controlCenter.stopSensorPolling() }
    }

    @ViewBuilder
    private var sensorLines: some View {
        if controlCenter.sensors.isEmpty && controlCenter.fans.isEmpty {
            line("no SMC keys responded on this machine", tint: .orange)
            if let reason = controlCenter.host.smcAccess.explanation {
                line("reason: \(reason)", tint: .secondary)
            }
        } else {
            ForEach(controlCenter.sensors) { sensor in
                line("\(sensor.key)  \(pad(sensor.label, 20))  \(String(format: "%7.2f", sensor.celsius)) C", tint: .green)
            }
            ForEach(controlCenter.fans) { fan in
                line("F\(fan.index)Ac  \(pad("Fan \(fan.index + 1) actual", 20))  \(String(format: "%7.0f", fan.currentRPM)) rpm", tint: .cyan)
                if let target = fan.targetRPM {
                    line("F\(fan.index)Tg  \(pad("Fan \(fan.index + 1) target", 20))  \(String(format: "%7.0f", target)) rpm", tint: .cyan)
                }
            }
            ForEach(controlCenter.powerReadings) { reading in
                line("\(reading.key)  \(pad(reading.label, 20))  \(String(format: "%7.2f", reading.watts)) W", tint: .yellow)
            }
        }
    }

    @ViewBuilder
    private var capabilityLines: some View {
        line("model      \(controlCenter.host.modelIdentifier)", tint: .secondary)
        line("chip       \(controlCenter.host.chipName)", tint: .secondary)
        line("os         \(controlCenter.host.osVersion)", tint: .secondary)
        line("battery    \(controlCenter.host.hasBattery ? "present" : "absent")", tint: .secondary)
        line("", tint: .secondary)

        ForEach(controlCenter.descriptors) { descriptor in
            let status = statusToken(descriptor.state)
            line("\(pad(descriptor.id.rawValue, 22)) \(status)", tint: descriptor.state.isSupported ? .green : .orange)
            if let explanation = descriptor.state.explanation {
                line("    \(explanation)", tint: .secondary)
            }
        }
    }

    @ViewBuilder
    private var samplingLines: some View {
        if let metrics = collector.latestMetrics {
            line("timestamp        \(metrics.timestamp.formatted(date: .omitted, time: .standard))", tint: .secondary)
            line("processes        \(collector.latestProcesses.count)", tint: .secondary)
            line("buffered samples \(collector.recentSamples.count)", tint: .secondary)
            line("cpu total        \(String(format: "%.3f", metrics.cpu.totalUsage))%", tint: .green)
            line("cpu cores        \(metrics.cpu.perCoreUsage.map { String(format: "%.0f", $0) }.joined(separator: " "))", tint: .green)
            line("mem pressure     \(metrics.memory.pressure.rawValue)", tint: .green)
            line("mem swap         \(Formatters.bytes(metrics.memory.swapUsedBytes))", tint: .green)
            line("gpu util         \(metrics.gpu.utilization.map { String(format: "%.3f%%", $0) } ?? "unpublished")", tint: .green)
            line("gpu clock        \(metrics.gpu.frequencyMHz.map { String(format: "%.0f MHz", $0) } ?? "unpublished")", tint: .green)
            line("gpu temp         \(metrics.gpu.temperatureC.map { String(format: "%.0f C", $0) } ?? "unpublished")", tint: .green)
            line("gpu power        \(metrics.gpu.powerWatts.map { String(format: "%.1f W", $0) } ?? "unpublished")", tint: .green)
            line("gpu device       \(metrics.gpu.deviceName)", tint: .secondary)
            line("thermal state    \(metrics.thermal.thermalState.rawValue)", tint: .green)
            line("throttling       \(metrics.thermal.isThrottling)", tint: metrics.thermal.isThrottling ? .red : .green)
            line("uptime           \(Int(metrics.uptime)) s", tint: .secondary)
        } else {
            line("waiting for the first sample…", tint: .secondary)
        }
    }

    private func line(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 10.5, design: .monospaced))
            .foregroundStyle(tint)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func pad(_ text: String, _ width: Int) -> String {
        text.count >= width ? String(text.prefix(width)) : text.padding(toLength: width, withPad: " ", startingAt: 0)
    }

    private func statusToken(_ state: CapabilityState) -> String {
        switch state {
        case .supported: "SUPPORTED"
        case .unsupported: "UNSUPPORTED"
        case .requiresPrivileges: "NEEDS-PRIVILEGES"
        }
    }
}

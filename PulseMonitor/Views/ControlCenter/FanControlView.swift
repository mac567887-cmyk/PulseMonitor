import SwiftUI
import Charts

/// Fan and sensor readout.
///
/// Manual fan control is only ever offered when `HostCapabilities.fanControl`
/// reports it as supported. On Apple Silicon the controls are replaced by the
/// hardware's own restriction; on Intel without a privileged helper they are
/// shown disabled with the reason. No slider here ever moves a fan it cannot
/// actually reach.
public struct FanControlView: View {
    @Bindable var viewModel: ControlCenterViewModel

    public init(viewModel: ControlCenterViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.gridSpacing) {
                capabilityBanner

                if viewModel.fans.isEmpty {
                    noFansCard
                } else {
                    ForEach(viewModel.fans) { fan in
                        fanCard(fan)
                    }
                }

                if !viewModel.sensors.isEmpty {
                    sensorGrid
                }

                if !viewModel.powerReadings.isEmpty {
                    powerCard
                }
            }
            .padding(DesignTokens.sectionSpacing)
        }
        .background(AmbientBackdrop())
        .navigationTitle("Fans & Sensors")
        .task {
            await viewModel.load()
            viewModel.startSensorPolling()
        }
        .onDisappear { viewModel.stopSensorPolling() }
    }

    // MARK: - Capability

    private var capabilityBanner: some View {
        GlassSection(title: "Manual Fan Control", systemImage: "fan.fill") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: viewModel.host.fanControl.isSupported ? "checkmark.seal.fill" : "lock.fill")
                        .foregroundStyle(viewModel.host.fanControl.isSupported ? .green : .orange)
                    Text(viewModel.host.fanControl.isSupported ? "Available on this Mac" : "Not available on this Mac")
                        .font(.headline)
                }

                if let explanation = viewModel.host.fanControl.explanation {
                    Text(explanation)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("\(viewModel.host.modelIdentifier) · \(viewModel.host.chipName)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                if !viewModel.host.fanControl.isSupported {
                    Divider().padding(.vertical, 2)
                    // Spell out exactly what is and is not on offer.
                    Label(
                        "Fan speeds below are live readings from the SMC. PulseMonitor can show them but cannot change them.",
                        systemImage: "info.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var noFansCard: some View {
        GlassSection(title: "Fan Readings", systemImage: "fan") {
            VStack(alignment: .leading, spacing: 8) {
                Text("No fan readings available")
                    .font(.headline)
                if let explanation = viewModel.host.fanReadout.explanation {
                    Text(explanation)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("This Mac reports no fans, which is expected on fanless models such as the MacBook Air.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Fans

    private func fanCard(_ fan: SMCService.FanReading) -> some View {
        GlassSection(title: "Fan \(fan.index + 1)", systemImage: "fan.fill") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(Int(fan.currentRPM))")
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("RPM")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let target = fan.targetRPM, abs(target - fan.currentRPM) > 50 {
                        VStack(alignment: .trailing, spacing: 0) {
                            Text("target")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Text("\(Int(target)) RPM")
                                .font(.caption)
                                .monospacedDigit()
                        }
                    }
                }
                .animation(DesignTokens.Motion.value, value: fan.currentRPM)

                if let fraction = fan.loadFraction {
                    VStack(alignment: .leading, spacing: 4) {
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.primary.opacity(0.1))
                                Capsule()
                                    .fill(LinearGradient(
                                        colors: [.blue, fraction > 0.8 ? .orange : .cyan],
                                        startPoint: .leading, endPoint: .trailing
                                    ))
                                    .frame(width: proxy.size.width * fraction)
                            }
                        }
                        .frame(height: 8)
                        .animation(DesignTokens.Motion.value, value: fraction)

                        HStack {
                            Text("\(Int(fan.minimumRPM ?? 0)) RPM")
                            Spacer()
                            Text("\(Int(fraction * 100))% of range")
                            Spacer()
                            Text("\(Int(fan.maximumRPM ?? 0)) RPM")
                        }
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                    }
                }

                // The manual control surface, permanently disabled unless the
                // capability layer says otherwise.
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Manual speed")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Slider(value: .constant(fan.currentRPM), in: (fan.minimumRPM ?? 0)...(fan.maximumRPM ?? 6000))
                            .disabled(!viewModel.host.fanControl.isSupported)
                            .opacity(viewModel.host.fanControl.isSupported ? 1 : 0.35)
                    }
                    CapabilityNotice(state: viewModel.host.fanControl)
                }
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Sensors

    private var sensorGrid: some View {
        GlassSection(title: "Temperature Sensors", systemImage: "thermometer.medium") {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 150, maximum: 240), spacing: 10)],
                spacing: 10
            ) {
                ForEach(viewModel.sensors) { sensor in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(sensor.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text("\(Int(sensor.celsius))")
                                .font(.system(size: 20, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .contentTransition(.numericText())
                                .foregroundStyle(tint(for: sensor.celsius))
                            Text("°C")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(sensor.key)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.quaternary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: DesignTokens.compactCornerRadius, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                    )
                    .animation(DesignTokens.Motion.value, value: sensor.celsius)
                }
            }
        }
    }

    private func tint(for celsius: Double) -> Color {
        switch celsius {
        case ..<55: .green
        case ..<75: .yellow
        case ..<90: .orange
        default: .red
        }
    }

    private var powerCard: some View {
        GlassSection(title: "Power Rails", systemImage: "bolt.square.fill") {
            VStack(spacing: 8) {
                ForEach(viewModel.powerReadings) { reading in
                    HStack {
                        Text(reading.label)
                            .font(.callout)
                        Spacer()
                        Text(String(format: "%.1f W", reading.watts))
                            .font(.callout.weight(.medium))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }
                }
            }
            .animation(DesignTokens.Motion.value, value: viewModel.powerReadings)
        }
    }
}

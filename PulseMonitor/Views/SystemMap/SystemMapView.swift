import SwiftUI

/// Interactive system map.
///
/// Each node is a real subsystem with live values behind it. Nodes whose sensors
/// this Mac does not publish are drawn dimmed and say what is missing when
/// selected, rather than being omitted or shown at zero.
public struct SystemMapView: View {
    let collector: MetricsCollector
    let host: HostCapabilities

    @State private var selected: Node.Kind?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(collector: MetricsCollector, host: HostCapabilities) {
        self.collector = collector
        self.host = host
    }

    /// One hardware subsystem on the map.
    struct Node: Identifiable {
        enum Kind: String, CaseIterable, Identifiable {
            case cpu, gpu, memory, storage, battery, fans, network, sensors
            var id: String { rawValue }
        }

        let id: Kind
        let title: String
        let symbol: String
        let value: String?
        let fraction: Double?
        let isAvailable: Bool
        let unavailableReason: String?
        let detail: [(String, String)]
    }

    public var body: some View {
        GeometryReader { proxy in
            ZStack {
                AmbientBackdrop()

                connections(in: proxy.size)

                ForEach(nodes) { node in
                    nodeView(node)
                        .position(position(for: node.id, in: proxy.size))
                }
            }
            .overlay(alignment: .bottom) {
                if let selected, let node = nodes.first(where: { $0.id == selected }) {
                    inspector(node)
                        .padding(DesignTokens.sectionSpacing)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .navigationTitle("System Map")
        .animation(reduceMotion ? nil : DesignTokens.Motion.standard, value: selected)
    }

    // MARK: - Layout

    /// Radial arrangement: memory sits at the centre, everything else orbits it.
    private func position(for kind: Node.Kind, in size: CGSize) -> CGPoint {
        let center = CGPoint(x: size.width / 2, y: size.height / 2 - 40)
        guard kind != .memory else { return center }

        let orbit = Node.Kind.allCases.filter { $0 != .memory }
        guard let index = orbit.firstIndex(of: kind) else { return center }

        let angle = (Double(index) / Double(orbit.count)) * 2 * .pi - .pi / 2
        let radius = min(size.width, size.height) * 0.32
        return CGPoint(
            x: center.x + cos(angle) * radius,
            y: center.y + sin(angle) * radius
        )
    }

    private func connections(in size: CGSize) -> some View {
        Canvas { context, _ in
            let center = position(for: .memory, in: size)
            for kind in Node.Kind.allCases where kind != .memory {
                var path = Path()
                path.move(to: center)
                path.addLine(to: position(for: kind, in: size))
                context.stroke(
                    path,
                    with: .color(.primary.opacity(0.12)),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                )
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Nodes

    private func nodeView(_ node: Node) -> some View {
        let isSelected = selected == node.id

        return Button {
            selected = isSelected ? nil : node.id
        } label: {
            VStack(spacing: 5) {
                ZStack {
                    Circle()
                        .fill(.regularMaterial)
                        .overlay {
                            Circle().strokeBorder(
                                node.isAvailable ? Color.accentColor.opacity(isSelected ? 0.9 : 0.4) : Color.secondary.opacity(0.25),
                                lineWidth: isSelected ? 2 : 1
                            )
                        }

                    if let fraction = node.fraction {
                        Circle()
                            .trim(from: 0, to: fraction)
                            .stroke(
                                tint(for: fraction),
                                style: StrokeStyle(lineWidth: 3, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                            .padding(3)
                            .animation(DesignTokens.Motion.value, value: fraction)
                    }

                    Image(systemName: node.symbol)
                        .font(.system(size: 21))
                        .foregroundStyle(node.isAvailable ? Color.primary : Color.secondary)
                }
                .frame(width: 66, height: 66)
                .shadow(color: .black.opacity(isSelected ? 0.3 : 0.12), radius: isSelected ? 14 : 6, y: 4)

                Text(node.title)
                    .font(.caption.weight(.medium))
                Text(node.value ?? "n/a")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(node.isAvailable ? .secondary : .tertiary)
                    .contentTransition(.numericText())
            }
            .opacity(node.isAvailable ? 1 : 0.55)
            .scaleEffect(isSelected ? 1.08 : 1)
        }
        .buttonStyle(.plain)
    }

    private func tint(for fraction: Double) -> Color {
        switch fraction {
        case ..<0.6: .green
        case ..<0.85: .orange
        default: .red
        }
    }

    private func inspector(_ node: Node) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(node.title, systemImage: node.symbol).font(.headline)
                Spacer()
                Button {
                    selected = nil
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            if node.isAvailable {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 150, maximum: 260), spacing: 8)],
                    spacing: 6
                ) {
                    ForEach(node.detail, id: \.0) { label, value in
                        HStack {
                            Text(label).font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text(value).font(.caption).monospacedDigit()
                        }
                    }
                }
            } else {
                Text(node.unavailableReason ?? "This subsystem does not publish readings on this Mac.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: 620)
        .glassCard(isElevated: true)
    }

    // MARK: - Data

    private var nodes: [Node] {
        let metrics = collector.latestMetrics

        return [
            Node(
                id: .cpu,
                title: "CPU",
                symbol: "cpu",
                value: metrics.map { String(format: "%.0f%%", $0.cpu.totalUsage) },
                fraction: metrics.map { $0.cpu.totalUsage / 100 },
                isAvailable: metrics != nil,
                unavailableReason: nil,
                detail: metrics.map { m in
                    var rows: [(String, String)] = [
                        ("Model", m.cpu.brand),
                        ("Cores", "\(m.cpu.physicalCoreCount) physical / \(m.cpu.logicalCoreCount) logical"),
                        ("User", String(format: "%.1f%%", m.cpu.userUsage)),
                        ("System", String(format: "%.1f%%", m.cpu.systemUsage)),
                        ("Load average", String(format: "%.2f", m.cpu.loadAverage1)),
                        ("Threads", "\(m.cpu.threadCount)")
                    ]
                    if let frequency = m.cpu.currentFrequencyMHz {
                        rows.append(("Frequency", String(format: "%.0f MHz", frequency)))
                    }
                    return rows
                } ?? []
            ),
            Node(
                id: .gpu,
                title: "GPU",
                symbol: "cube",
                value: metrics.map { String(format: "%.0f%%", $0.gpu.utilization) },
                fraction: metrics.map { $0.gpu.utilization / 100 },
                isAvailable: metrics != nil,
                unavailableReason: nil,
                detail: metrics.map { m in
                    var rows: [(String, String)] = [("Device", m.gpu.deviceName)]
                    if let used = m.gpu.memoryUsedBytes {
                        rows.append(("Memory in use", Formatters.bytes(used)))
                    }
                    if let windowServer = m.gpu.windowServerCPU {
                        rows.append(("WindowServer CPU", String(format: "%.1f%%", windowServer)))
                    }
                    rows.append(("Metal active", m.gpu.isMetalActive ? "Yes" : "No"))
                    return rows
                } ?? []
            ),
            Node(
                id: .memory,
                title: "Memory",
                symbol: "memorychip",
                value: metrics.map { String(format: "%.0f%%", $0.memory.usagePercent) },
                fraction: metrics.map { $0.memory.usagePercent / 100 },
                isAvailable: metrics != nil,
                unavailableReason: nil,
                detail: metrics.map { m in
                    [
                        ("Total", Formatters.bytes(m.memory.totalBytes)),
                        ("Used", Formatters.bytes(m.memory.usedBytes)),
                        ("App memory", Formatters.bytes(m.memory.appMemoryBytes)),
                        ("Wired", Formatters.bytes(m.memory.wiredBytes)),
                        ("Compressed", Formatters.bytes(m.memory.compressedBytes)),
                        ("Swap", Formatters.bytes(m.memory.swapUsedBytes)),
                        ("Pressure", m.memory.pressure.displayName)
                    ]
                } ?? []
            ),
            Node(
                id: .storage,
                title: "Storage",
                symbol: "internaldrive",
                value: metrics?.storage.volumes.first(where: \.isRoot).map { String(format: "%.0f%%", $0.usedPercent) },
                fraction: metrics?.storage.volumes.first(where: \.isRoot).map { $0.usedPercent / 100 },
                isAvailable: metrics?.storage.volumes.isEmpty == false,
                unavailableReason: nil,
                detail: metrics.map { m in
                    var rows: [(String, String)] = []
                    if let root = m.storage.volumes.first(where: \.isRoot) {
                        rows.append(("Volume", root.name))
                        rows.append(("Free", Formatters.bytes(root.freeBytes)))
                        rows.append(("Total", Formatters.bytes(root.totalBytes)))
                        rows.append(("Media", root.isSSD ? "Solid state" : "Rotational"))
                    }
                    rows.append(("Read", "\(Formatters.bytes(UInt64(max(0, m.storage.readBytesPerSec))))/s"))
                    rows.append(("Write", "\(Formatters.bytes(UInt64(max(0, m.storage.writeBytesPerSec))))/s"))
                    rows.append(("SMART", m.storage.smartHealth.displayName))
                    return rows
                } ?? []
            ),
            Node(
                id: .battery,
                title: "Battery",
                symbol: "battery.75",
                value: metrics?.battery.chargePercent.map { String(format: "%.0f%%", $0) },
                fraction: metrics?.battery.chargePercent.map { $0 / 100 },
                isAvailable: metrics?.battery.isPresent == true,
                unavailableReason: "This Mac has no internal battery.",
                detail: metrics.map { m in
                    var rows: [(String, String)] = [("Source", m.battery.powerSource.rawValue)]
                    if let health = m.battery.healthPercent {
                        rows.append(("Health", String(format: "%.0f%%", health)))
                    }
                    if let cycles = m.battery.cycleCount {
                        rows.append(("Cycles", "\(cycles)"))
                    }
                    if let voltage = m.battery.voltagemV {
                        rows.append(("Voltage", String(format: "%.2f V", voltage / 1000)))
                    }
                    if let wattage = m.battery.wattage {
                        rows.append(("Power", String(format: "%.1f W", wattage)))
                    }
                    if let remaining = m.battery.timeRemainingMinutes {
                        rows.append(("Remaining", "\(remaining / 60)h \(remaining % 60)m"))
                    }
                    return rows
                } ?? []
            ),
            Node(
                id: .fans,
                title: "Fans",
                symbol: "fan.fill",
                value: metrics?.thermal.fanSpeedsRPM.first.map { "\(Int($0.rpm)) RPM" },
                fraction: metrics?.thermal.fanSpeedsRPM.first.flatMap { fan in
                    fan.maxRPM.map { fan.rpm / $0 }
                },
                isAvailable: metrics?.thermal.fanSpeedsRPM.isEmpty == false,
                unavailableReason: host.fanReadout.explanation
                    ?? "No fan readings are published on this Mac.",
                detail: metrics?.thermal.fanSpeedsRPM.enumerated().map { index, fan in
                    ("Fan \(index + 1)", "\(Int(fan.rpm)) RPM")
                } ?? []
            ),
            Node(
                id: .network,
                title: "Network",
                symbol: "network",
                value: metrics.map { "\(Formatters.bytes(UInt64(max(0, $0.network.bytesInPerSec))))/s" },
                fraction: nil,
                isAvailable: metrics != nil,
                unavailableReason: nil,
                detail: metrics.map { m in
                    var rows: [(String, String)] = [
                        ("Down", "\(Formatters.bytes(UInt64(max(0, m.network.bytesInPerSec))))/s"),
                        ("Up", "\(Formatters.bytes(UInt64(max(0, m.network.bytesOutPerSec))))/s"),
                        ("Connections", "\(m.network.activeConnections)")
                    ]
                    if let latency = m.network.latencyMs {
                        rows.append(("Latency", String(format: "%.0f ms", latency)))
                    }
                    for interface in m.network.interfaces.filter(\.isActive).prefix(3) {
                        rows.append((interface.displayName, interface.kind))
                    }
                    return rows
                } ?? []
            ),
            Node(
                id: .sensors,
                title: "Thermal",
                symbol: "thermometer.medium",
                value: metrics?.thermal.cpuTemperatureC.map { String(format: "%.0f°C", $0) },
                fraction: metrics?.thermal.cpuTemperatureC.map { min(1, max(0, ($0 - 40) / 60)) },
                isAvailable: metrics?.thermal.cpuTemperatureC != nil,
                unavailableReason: host.smcAccess.explanation
                    ?? "No on-die temperature sensor is readable on this Mac.",
                detail: metrics.map { m in
                    var rows: [(String, String)] = [("Thermal state", m.thermal.thermalState.displayName)]
                    if let cpu = m.thermal.cpuTemperatureC {
                        rows.append(("CPU", String(format: "%.0f°C", cpu)))
                    }
                    if let gpu = m.thermal.gpuTemperatureC {
                        rows.append(("GPU", String(format: "%.0f°C", gpu)))
                    }
                    if let battery = m.thermal.batteryTemperatureC {
                        rows.append(("Battery", String(format: "%.0f°C", battery)))
                    }
                    rows.append(("Throttling", m.thermal.isThrottling ? "Yes" : "No"))
                    return rows
                } ?? []
            )
        ]
    }
}

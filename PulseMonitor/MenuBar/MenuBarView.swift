import SwiftUI
import AppKit

public struct MenuBarLabel: View {
    @Bindable var container: AppContainer

    public var body: some View {
        let metrics = container.metricsCollector.latestMetrics
        let text: String = {
            switch container.settings.menuBarMetric {
            case .cpu:
                return String(format: "CPU %.0f%%", metrics?.cpu.totalUsage ?? 0)
            case .memory:
                return String(format: "MEM %.0f%%", metrics?.memory.usagePercent ?? 0)
            case .temperature:
                if let t = metrics?.thermal.cpuTemperatureC ?? metrics?.thermal.batteryTemperatureC {
                    return String(format: "%.0f°C", t)
                }
                return metrics?.thermal.thermalState.displayName ?? "Therm"
            case .network:
                return Formatters.bytesPerSecond(metrics?.network.bytesInPerSec ?? 0)
            case .battery:
                if let c = metrics?.battery.chargePercent, metrics?.battery.isPresent == true {
                    return String(format: "BAT %.0f%%", c)
                }
                return "AC"
            }
        }()
        Text(text)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .monospacedDigit()
    }
}

public struct MenuBarView: View {
    @Bindable var container: AppContainer

    public var body: some View {
        let m = container.metricsCollector.latestMetrics
        Button("PulseMonitor") {}
            .disabled(true)
        Divider()
        Text(String(format: "CPU  %.1f%%", m?.cpu.totalUsage ?? 0))
        Text(String(format: "GPU  %.1f%%", m?.gpu.utilization ?? 0))
        Text(String(format: "MEM  %.1f%% · %@", m?.memory.usagePercent ?? 0, m?.memory.pressure.displayName ?? "—"))
        Text("Thermal  \(m?.thermal.thermalState.displayName ?? "—")")
        if let finding = container.metricsCollector.latestAnalysis?.primaryBottleneck {
            Divider()
            Text(finding.title)
            Text(finding.summary).lineLimit(3)
        }
        Divider()
        Button("Open PulseMonitor") {
            if let delegate = NSApp.delegate as? AppDelegate {
                delegate.ensureVisibleWindow()
            } else {
                NSApp.activate(ignoringOtherApps: true)
                for window in NSApp.windows where window.canBecomeMain {
                    window.makeKeyAndOrderFront(nil)
                    break
                }
            }
        }
        Button("Quit PulseMonitor") {
            NSApp.terminate(nil)
        }
    }
}

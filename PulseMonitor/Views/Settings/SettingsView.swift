import SwiftUI

public struct SettingsView: View {
    @Bindable var viewModel: SettingsViewModel

    public var body: some View {
        Form {
            Section("Sampling") {
                Slider(value: $viewModel.settings.refreshIntervalSeconds, in: 0.5...5, step: 0.5) {
                    Text("Refresh Interval")
                } minimumValueLabel: {
                    Text("0.5s")
                } maximumValueLabel: {
                    Text("5s")
                }
                Text("Current: \(String(format: "%.1fs", viewModel.settings.refreshIntervalSeconds))")
                    .foregroundStyle(.secondary)
                Slider(value: $viewModel.settings.graphDurationSeconds, in: 30...600, step: 30) {
                    Text("Graph Duration")
                }
            }
            Section("History") {
                Picker("Retention", selection: $viewModel.settings.historyRetention) {
                    ForEach(HistoryRetention.allCases) { item in
                        Text(item.displayName).tag(item)
                    }
                }
            }
            Section("Alerts") {
                Toggle("Enable Notifications", isOn: $viewModel.settings.notificationsEnabled)
                Slider(value: $viewModel.settings.cpuAlertThreshold, in: 50...100, step: 1) {
                    Text("CPU Alert Threshold")
                }
                Slider(value: $viewModel.settings.temperatureAlertC, in: 70...110, step: 1) {
                    Text("Temperature Alert (°C)")
                }
                Toggle("Memory Pressure Alerts", isOn: $viewModel.settings.memoryPressureAlerts)
            }
            Section("Appearance") {
                Picker("Theme", selection: $viewModel.settings.appearance) {
                    ForEach(AppSettings.AppAppearance.allCases) { item in
                        Text(item.displayName).tag(item)
                    }
                }
                Toggle("Menu Bar Widget", isOn: $viewModel.settings.showMenuBarExtra)
                Picker("Menu Bar Metric", selection: $viewModel.settings.menuBarMetric) {
                    ForEach(AppSettings.MenuBarMetric.allCases) { item in
                        Text(item.displayName).tag(item)
                    }
                }
            }
            Section("Privacy") {
                LabeledContent("Telemetry", value: "None")
                LabeledContent("Analytics", value: "None")
                LabeledContent("Network Requirement", value: "Not required")
                Text("All diagnostics run locally on your Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(maxWidth: 720)
    }
}

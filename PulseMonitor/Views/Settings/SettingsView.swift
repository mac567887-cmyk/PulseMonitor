import SwiftUI

/// Application settings.
///
/// Split into tabs so the version 2 surfaces (appearance, overlay, developer
/// tools) do not bury the sampling and alert controls.
public struct SettingsView: View {
    @Bindable var viewModel: SettingsViewModel

    public init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        TabView {
            general.tabItem { Label("General", systemImage: "gearshape") }
            appearance.tabItem { Label("Appearance", systemImage: "paintpalette") }
            overlay.tabItem { Label("Overlay", systemImage: "rectangle.on.rectangle.angled") }
            advanced.tabItem { Label("Advanced", systemImage: "hammer") }
            privacy.tabItem { Label("Privacy", systemImage: "lock.shield") }
        }
        .frame(maxWidth: 720)
    }

    // MARK: - General

    private var general: some View {
        Form {
            Section("Sampling") {
                Slider(value: $viewModel.settings.refreshIntervalSeconds, in: 0.5...10, step: 0.5) {
                    Text("Refresh Interval")
                } minimumValueLabel: {
                    Text("0.5s")
                } maximumValueLabel: {
                    Text("10s")
                }
                LabeledContent(
                    "Current",
                    value: String(format: "%.1f seconds", viewModel.settings.refreshIntervalSeconds)
                )
                Text("Longer intervals reduce PulseMonitor's own CPU cost. Process enumeration is the most expensive part of each sample.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Slider(value: $viewModel.settings.graphDurationSeconds, in: 30...900, step: 30) {
                    Text("Graph Duration")
                }
                LabeledContent(
                    "Window",
                    value: "\(Int(viewModel.settings.graphDurationSeconds / 60)) minutes"
                )
            }

            Section("History") {
                Picker("Retention", selection: $viewModel.settings.historyRetention) {
                    ForEach(HistoryRetention.allCases) { item in
                        Text(item.displayName).tag(item)
                    }
                }
                Text("Samples are written to a local SQLite database and pruned beyond this age.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Alerts") {
                Toggle("Enable Notifications", isOn: $viewModel.settings.notificationsEnabled)
                Slider(value: $viewModel.settings.cpuAlertThreshold, in: 50...100, step: 1) {
                    Text("CPU Alert Threshold")
                }
                LabeledContent("CPU", value: "\(Int(viewModel.settings.cpuAlertThreshold))%")
                Slider(value: $viewModel.settings.temperatureAlertC, in: 70...110, step: 1) {
                    Text("Temperature Alert")
                }
                LabeledContent("Temperature", value: "\(Int(viewModel.settings.temperatureAlertC))°C")
                Toggle("Memory Pressure Alerts", isOn: $viewModel.settings.memoryPressureAlerts)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Appearance

    private var appearance: some View {
        Form {
            Section("Theme") {
                Picker("Theme", selection: $viewModel.settings.theme) {
                    ForEach(Theme.allCases) { theme in
                        Text(theme.displayName).tag(theme)
                    }
                }
                .pickerStyle(.menu)

                // Live sample so the choice is visible without leaving Settings.
                HStack(spacing: 10) {
                    ForEach([viewModel.settings.theme], id: \.self) { theme in
                        Circle().fill(theme.accent).frame(width: 18, height: 18)
                        Circle().fill(theme.secondaryAccent).frame(width: 18, height: 18)
                        Text(theme.cardMaterial == nil ? "Pure black surfaces" : "Translucent surfaces")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text("OLED disables translucency and shadows so unlit pixels stay fully off.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Menu Bar") {
                Toggle("Menu Bar Widget", isOn: $viewModel.settings.showMenuBarExtra)
                Picker("Metric", selection: $viewModel.settings.menuBarMetric) {
                    ForEach(AppSettings.MenuBarMetric.allCases) { item in
                        Text(item.displayName).tag(item)
                    }
                }
                .disabled(!viewModel.settings.showMenuBarExtra)
            }

            Section("Live Backdrop") {
                Toggle("Animate in-app backdrop", isOn: $viewModel.liveWallpaper.liveBackdropEnabled)
                Text("Advances the accent wash every few seconds. Off by default so the monitor itself stays cheap to leave open.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Desktop Wallpaper Slideshow") {
                LabeledContent("Folder") {
                    Text(viewModel.liveWallpaper.folderURL?.lastPathComponent ?? "None")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Images", value: "\(viewModel.liveWallpaper.imageURLs.count)")
                Slider(value: $viewModel.liveWallpaper.intervalSeconds, in: 30...600, step: 15) {
                    Text("Interval")
                }
                LabeledContent(
                    "Interval",
                    value: "\(Int(viewModel.liveWallpaper.intervalSeconds))s"
                )
                HStack {
                    Button("Choose Folder…") { viewModel.liveWallpaper.chooseFolder() }
                    Button("Apply Current") { viewModel.liveWallpaper.applyCurrent() }
                    if viewModel.liveWallpaper.isRotating {
                        Button("Stop Rotation") { viewModel.liveWallpaper.stopRotation() }
                    } else {
                        Button("Start Rotation") { viewModel.liveWallpaper.startRotation() }
                    }
                }
                if let status = viewModel.liveWallpaper.statusMessage {
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Motion") {
                Text("PulseMonitor honours the system Reduce Motion setting. When it is on, ambient gradients and shimmer animations stop and value changes update without easing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Overlay

    private var overlay: some View {
        Form {
            Section("Floating Overlay") {
                Toggle("Show Overlay", isOn: $viewModel.settings.overlayEnabled)

                Slider(value: $viewModel.settings.overlayOpacity, in: 0.2...1) {
                    Text("Opacity")
                }
                .disabled(!viewModel.settings.overlayEnabled)
                LabeledContent("Opacity", value: "\(Int(viewModel.settings.overlayOpacity * 100))%")

                Toggle("Always on Top", isOn: $viewModel.settings.overlayAlwaysOnTop)
                    .disabled(!viewModel.settings.overlayEnabled)

                Toggle("Game Mode", isOn: $viewModel.settings.overlayGameMode)
                    .disabled(!viewModel.settings.overlayEnabled)
                Text("Game Mode raises the overlay above full-screen windows and makes it click-through so it cannot interrupt play.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ColorPicker(
                    "Accent Colour",
                    selection: Binding(
                        get: { Color(hex: viewModel.settings.overlayTintHex) ?? .blue },
                        set: { viewModel.settings.overlayTintHex = $0.hexString }
                    ),
                    supportsOpacity: false
                )
                .disabled(!viewModel.settings.overlayEnabled)
            }

            Section("Metrics") {
                ForEach(AppSettings.OverlayMetric.allCases) { metric in
                    Toggle(metric.displayName, isOn: Binding(
                        get: { viewModel.settings.overlayMetrics.contains(metric) },
                        set: { isOn in
                            var updated = viewModel.settings.overlayMetrics
                            if isOn { updated.insert(metric) } else { updated.remove(metric) }
                            viewModel.settings.overlayMetrics = updated
                        }
                    ))
                    .disabled(!viewModel.settings.overlayEnabled)
                }

                Label(
                    "Frame rate is not offered. Reading another application's frame rate requires private APIs or Metal's own HUD, so PulseMonitor does not show a number it cannot measure.",
                    systemImage: "info.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Advanced

    private var advanced: some View {
        Form {
            Section("Automation") {
                Toggle("Run automation rules", isOn: $viewModel.settings.automationEnabled)
                Text("Rules are configured in the Profiles module.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Developer") {
                Toggle("Developer Mode", isOn: $viewModel.settings.developerModeEnabled)
                Text("Adds a live console to the Dashboard showing raw sensor keys, sampling timings and the capability decisions behind every gated control.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Athena AI (PIE)") {
                Toggle("On-device Learning", isOn: $viewModel.settings.aiLearningEnabled)
                Toggle("Show PIE Reasoning", isOn: $viewModel.settings.aiDeveloperReasoning)
                Picker("Insight Detail", selection: $viewModel.settings.aiInsightDetail) {
                    ForEach(AppSettings.AIInsightDetail.allCases) { Text($0.displayName).tag($0) }
                }
                Picker("Prediction Frequency", selection: $viewModel.settings.aiPredictionFrequency) {
                    ForEach(AppSettings.AIPredictionFrequency.allCases) { Text($0.displayName).tag($0) }
                }
                Picker("Notification Style", selection: $viewModel.settings.aiNotificationStyle) {
                    ForEach(AppSettings.AINotificationStyle.allCases) { Text($0.displayName).tag($0) }
                }
                VStack(alignment: .leading) {
                    Text("Confidence Threshold: \(Int(viewModel.settings.aiConfidenceThreshold))%")
                    Slider(value: $viewModel.settings.aiConfidenceThreshold, in: 30...90, step: 5)
                }
                Text("Athena runs fully offline. Habits stay in Application Support. Predictions are trend estimates labeled as such — never fabricated sensors.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Privacy

    private var privacy: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    BrandMark(size: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("PulseMonitor")
                            .font(.title2.weight(.semibold))
                        Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0.0")")
                            .foregroundStyle(.secondary)
                        Text("Local-only hardware control centre")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }

            Section("Data Handling") {
                LabeledContent("Telemetry", value: "None")
                LabeledContent("Analytics", value: "None")
                LabeledContent("Network requirement", value: "None")
                LabeledContent("Account", value: "Not required")
            }

            Section("Where data is stored") {
                Text("Metrics history, benchmark scores, automation rules and the event log are written to ~/Library/Application Support/PulseMonitor and never leave your Mac.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("What the app reads") {
                Text("PulseMonitor reads kernel statistics, IOKit sensors, process tables and the diagnostic reports macOS already writes. It does not read documents, messages or browsing data.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

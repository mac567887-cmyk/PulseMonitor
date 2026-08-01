import SwiftUI

/// System Control Center.
///
/// Every row consults `ControlCenterViewModel.state(for:)` first. Controls that
/// macOS will not let an unprivileged app change are rendered disabled with the
/// specific reason underneath, never hidden and never fake.
public struct ControlCenterView: View {
    @Bindable var viewModel: ControlCenterViewModel
    @Environment(\.theme) private var theme

    public init(viewModel: ControlCenterViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 320, maximum: 520), spacing: DesignTokens.gridSpacing)],
                spacing: DesignTokens.gridSpacing
            ) {
                soundSection
                displaySection
                appearanceSection
                dockSection
                powerSection
                loginItemsSection
            }
            .padding(DesignTokens.sectionSpacing)
        }
        .background(AmbientBackdrop())
        .navigationTitle("Control Center")
        .task { await viewModel.load() }
        .alert(
            "That change did not apply",
            isPresented: Binding(
                get: { viewModel.lastError != nil },
                set: { if !$0 { viewModel.dismissError() } }
            )
        ) {
            Button("OK") { viewModel.dismissError() }
        } message: {
            Text(viewModel.lastError ?? "")
        }
    }

    // MARK: - Sections

    private var soundSection: some View {
        GlassSection(title: "Sound", systemImage: "speaker.wave.2.fill") {
            VStack(alignment: .leading, spacing: 14) {
                ControlRow(
                    title: "Output Volume",
                    symbol: "speaker.wave.3.fill",
                    state: viewModel.state(for: .outputVolume)
                ) {
                    HStack(spacing: 10) {
                        Slider(
                            value: Binding(
                                get: { viewModel.volume },
                                set: { newValue in
                                    viewModel.volume = newValue
                                    Task { await viewModel.applyVolume(newValue) }
                                }
                            ),
                            in: 0...1
                        )
                        Text("\(Int(viewModel.volume * 100))%")
                            .font(.caption)
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                }

                ControlRow(
                    title: "Mute",
                    symbol: "speaker.slash.fill",
                    state: viewModel.state(for: .outputMute)
                ) {
                    Toggle("", isOn: Binding(
                        get: { viewModel.isMuted },
                        set: { newValue in
                            viewModel.isMuted = newValue
                            Task { await viewModel.applyMute(newValue) }
                        }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
            }
        }
    }

    private var displaySection: some View {
        GlassSection(title: "Display", systemImage: "display") {
            VStack(alignment: .leading, spacing: 14) {
                ControlRow(
                    title: "Brightness",
                    symbol: "sun.max.fill",
                    state: viewModel.state(for: .displayBrightness)
                ) {
                    HStack(spacing: 10) {
                        Slider(
                            value: Binding(
                                get: { viewModel.brightness },
                                set: { newValue in
                                    viewModel.brightness = newValue
                                    Task { await viewModel.applyBrightness(newValue) }
                                }
                            ),
                            in: 0...1
                        )
                        Text("\(Int(viewModel.brightness * 100))%")
                            .font(.caption)
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                }

                ControlRow(
                    title: "Night Shift",
                    symbol: "moon.fill",
                    state: viewModel.state(for: .nightShift)
                ) {
                    Toggle("", isOn: .constant(false)).labelsHidden().toggleStyle(.switch)
                }

                ControlRow(
                    title: "True Tone",
                    symbol: "sun.haze.fill",
                    state: viewModel.state(for: .trueTone)
                ) {
                    Toggle("", isOn: .constant(false)).labelsHidden().toggleStyle(.switch)
                }

                ControlRow(
                    title: "Keyboard Brightness",
                    symbol: "keyboard",
                    state: viewModel.state(for: .keyboardBrightness)
                ) {
                    Slider(value: .constant(0), in: 0...1)
                }
            }
        }
    }

    private var appearanceSection: some View {
        GlassSection(title: "Appearance", systemImage: "circle.lefthalf.filled") {
            VStack(alignment: .leading, spacing: 14) {
                ControlRow(
                    title: "Dark Mode",
                    symbol: "moon.stars.fill",
                    state: viewModel.state(for: .appearance)
                ) {
                    Toggle("", isOn: Binding(
                        get: { viewModel.isDarkMode },
                        set: { newValue in
                            viewModel.isDarkMode = newValue
                            Task { await viewModel.applyDarkMode(newValue) }
                        }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }

                ControlRow(
                    title: "Desktop Picture",
                    symbol: "photo.on.rectangle.angled",
                    state: viewModel.state(for: .wallpaper)
                ) {
                    Button("Choose…") {
                        Task { await viewModel.chooseWallpaper() }
                    }
                    .buttonStyle(.bordered)
                }

                ControlRow(
                    title: "Do Not Disturb",
                    symbol: "moon.zzz.fill",
                    state: viewModel.state(for: .doNotDisturb)
                ) {
                    Toggle("", isOn: .constant(false)).labelsHidden().toggleStyle(.switch)
                }
            }
        }
    }

    private var dockSection: some View {
        GlassSection(title: "Dock", systemImage: "dock.rectangle") {
            VStack(alignment: .leading, spacing: 14) {
                ControlRow(
                    title: "Automatically Hide",
                    symbol: "arrow.down.to.line",
                    state: viewModel.state(for: .dockAutohide)
                ) {
                    Toggle("", isOn: Binding(
                        get: { viewModel.dockAutohide },
                        set: { newValue in
                            viewModel.dockAutohide = newValue
                            Task { await viewModel.applyDockAutohide(newValue) }
                        }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }

                ControlRow(
                    title: "Icon Size",
                    symbol: "arrow.left.and.right",
                    state: viewModel.state(for: .dockSize)
                ) {
                    HStack(spacing: 10) {
                        Slider(
                            value: $viewModel.dockSize,
                            in: 16...128,
                            onEditingChanged: { editing in
                                // Only write on release; the Dock restarts on each change.
                                guard !editing else { return }
                                Task { await viewModel.applyDockSize(viewModel.dockSize) }
                            }
                        )
                        Text("\(Int(viewModel.dockSize))")
                            .font(.caption)
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                }

                Text("Changing Dock settings relaunches the Dock, which briefly hides it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var powerSection: some View {
        GlassSection(title: "Power", systemImage: "bolt.fill") {
            VStack(alignment: .leading, spacing: 14) {
                ControlRow(
                    title: "Low Power Mode",
                    symbol: "battery.25",
                    state: viewModel.state(for: .lowPowerMode)
                ) {
                    Toggle("", isOn: .constant(false)).labelsHidden().toggleStyle(.switch)
                }

                ControlRow(
                    title: "Automatic Graphics Switching",
                    symbol: "rectangle.on.rectangle",
                    state: viewModel.state(for: .gpuSwitching)
                ) {
                    Toggle("", isOn: .constant(false)).labelsHidden().toggleStyle(.switch)
                }

                if !viewModel.powerSettings.isEmpty {
                    Divider()
                    Text("Current power settings")
                        .font(.subheadline.weight(.medium))

                    // Read directly from pmset so these reflect the live configuration.
                    ForEach(Array(viewModel.powerSettings.keys.sorted()), id: \.self) { key in
                        HStack {
                            Text(Self.friendlyPowerKey(key))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(viewModel.powerSettings[key] ?? "")
                                .font(.caption)
                                .monospacedDigit()
                        }
                    }

                    Text("These values are read from pmset. Changing them requires administrator rights, so PulseMonitor shows them read-only.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 4)
                }
            }
        }
    }

    private var loginItemsSection: some View {
        GlassSection(title: "Login Items", systemImage: "person.crop.circle.badge.checkmark") {
            VStack(alignment: .leading, spacing: 10) {
                if viewModel.launchAgents.isEmpty {
                    Text("No user launch agents are installed for your account.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(viewModel.launchAgents.count) launch agents start with your account.")
                        .font(.callout)

                    ForEach(viewModel.launchAgents.prefix(12)) { agent in
                        HStack(spacing: 8) {
                            Image(systemName: agent.runAtLoad ? "play.circle.fill" : "pause.circle")
                                .foregroundStyle(agent.runAtLoad ? .green : .secondary)
                            Text(agent.label)
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                        }
                    }

                    if viewModel.launchAgents.count > 12 {
                        Text("and \(viewModel.launchAgents.count - 12) more")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Text("PulseMonitor lists these for review. Removing them is done in System Settings so nothing is disabled behind your back.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Button("Open Login Items in System Settings") {
                    Task { await viewModel.openLoginItems() }
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private static func friendlyPowerKey(_ key: String) -> String {
        switch key {
        case "displaysleep": "Display sleep (minutes)"
        case "disksleep": "Disk sleep (minutes)"
        case "sleep": "System sleep (minutes)"
        case "womp": "Wake for network access"
        case "powernap": "Power Nap"
        case "lowpowermode": "Low Power Mode"
        case "hibernatemode": "Hibernate mode"
        case "standby": "Standby"
        case "ttyskeepawake": "Prevent sleep while a terminal is active"
        case "gpuswitch": "Graphics switching"
        default: key.capitalized
        }
    }
}

/// One labelled control with its capability state resolved.
///
/// When the control is unavailable the accessory is disabled and dimmed, and the
/// reason appears directly beneath it.
private struct ControlRow<Accessory: View>: View {
    let title: String
    let symbol: String
    let state: CapabilityState
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .frame(width: 20)
                    .foregroundStyle(state.isSupported ? Color.accentColor : Color.secondary)
                Text(title)
                    .foregroundStyle(state.isSupported ? .primary : .secondary)
                Spacer(minLength: 12)
                accessory()
                    .disabled(!state.isSupported)
                    .opacity(state.isSupported ? 1 : 0.4)
                    .frame(maxWidth: 220)
            }
            CapabilityNotice(state: state)
                .padding(.leading, 30)
        }
    }
}

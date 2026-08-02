import SwiftUI

/// PulseMonitor application entry point.
///
/// The main window hosts the full navigation tree. Individual modules can also
/// be torn off into their own windows through the `module` scene, which reads
/// from the same collector so every window stays in step without extra polling.
@main
struct PulseMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var container = AppContainer()
    @State private var overlayController: OverlayWindowController?

    var body: some Scene {
        WindowGroup("PulseMonitor") {
            ContentView(container: container)
                .frame(minWidth: 1000, minHeight: 660)
                .environment(\.theme, container.settings.theme)
                .environment(\.liveBackdropEnabled, container.liveWallpaperService.liveBackdropEnabled)
                .preferredColorScheme(container.settings.theme.colorScheme)
                // Sampling is tied to the app, not to this window. Closing the
                // main window leaves the menu bar item and overlay running, and
                // both need a live collector behind them.
                .onAppear {
                    container.start()
                    syncOverlay()
                }
                .onChange(of: container.settings.overlayEnabled) { _, _ in syncOverlay() }
                .onChange(of: container.settings.overlayAlwaysOnTop) { _, _ in overlayController?.refresh() }
                .onChange(of: container.settings.overlayGameMode) { _, _ in overlayController?.refresh() }
        }
        .defaultSize(width: 1240, height: 800)
        .commands { commands }

        // Tear-off windows. Each takes the module identifier as its value, so
        // several can be open at once without colliding.
        WindowGroup("Module", id: "module", for: SidebarItem.self) { $item in
            ModuleWindow(container: container, item: item ?? .dashboard)
                .environment(\.theme, container.settings.theme)
                .preferredColorScheme(container.settings.theme.colorScheme)
        }
        .defaultSize(width: 900, height: 640)

        Settings {
            SettingsView(viewModel: container.settingsViewModel)
                .environment(\.theme, container.settings.theme)
                .frame(width: 560, height: 560)
        }

        // The setter must ignore no-op writes: MenuBarExtra pushes `isInserted` back on
        // every render, and @Observable notifies on each set even when the value is
        // unchanged, which would invalidate this body in a loop.
        MenuBarExtra(isInserted: Binding(
            get: { container.settings.showMenuBarExtra },
            set: { newValue in
                guard container.settings.showMenuBarExtra != newValue else { return }
                container.settings.showMenuBarExtra = newValue
            }
        )) {
            MenuBarView(container: container)
        } label: {
            MenuBarLabel(container: container)
        }
        .menuBarExtraStyle(.menu)
    }

    @CommandsBuilder
    private var commands: some Commands {
        // The default New Window item is kept deliberately. The app outlives its
        // main window — the menu bar item and the overlay hold it open — so
        // removing it would strand a user who closed that window with no way back.

        // Named "Modules" rather than "Window": a CommandMenu called Window does
        // not merge with the standard one, it sits beside it, leaving two menus
        // with the same name in the bar.
        CommandMenu("Modules") {
            ForEach(SidebarItem.allCases) { item in
                OpenModuleButton(item: item)
            }
        }

        CommandMenu("Monitoring") {
            Toggle("Performance Overlay", isOn: Binding(
                get: { container.settings.overlayEnabled },
                set: { container.settings.overlayEnabled = $0 }
            ))
            .keyboardShortcut("o", modifiers: [.command, .shift])

            Toggle("Game Mode Overlay", isOn: Binding(
                get: { container.settings.overlayGameMode },
                set: { container.settings.overlayGameMode = $0 }
            ))
            .disabled(!container.settings.overlayEnabled)

            Divider()

            Picker("Power Profile", selection: Binding(
                get: { container.settings.activeProfile },
                set: { container.powerProfileService.apply($0) }
            )) {
                ForEach(PowerProfile.Kind.allCases) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }
        }
    }

    /// Creates the overlay panel lazily and keeps it in sync with the setting.
    private func syncOverlay() {
        if container.settings.overlayEnabled {
            if overlayController == nil {
                overlayController = OverlayWindowController(
                    viewModel: container.overlayViewModel,
                    settings: container.settings
                )
            }
            overlayController?.show()
        } else {
            overlayController?.hide()
        }
    }
}

/// Menu item that opens one module in its own window.
private struct OpenModuleButton: View {
    let item: SidebarItem
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(item.title) {
            openWindow(id: "module", value: item)
        }
    }
}

/// Wrapper giving a torn-off module its own navigation chrome.
private struct ModuleWindow: View {
    let container: AppContainer
    let item: SidebarItem

    var body: some View {
        NavigationStack {
            ModuleDetail(container: container, item: item)
                .navigationTitle(item.title)
        }
        .frame(minWidth: 640, minHeight: 460)
    }
}

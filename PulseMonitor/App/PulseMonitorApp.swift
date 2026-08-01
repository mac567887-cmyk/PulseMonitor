import SwiftUI

/// PulseMonitor application entry point.
@main
struct PulseMonitorApp: App {
    @State private var container = AppContainer()

    var body: some Scene {
        WindowGroup("PulseMonitor") {
            ContentView(container: container)
                .frame(minWidth: 980, minHeight: 640)
                .onAppear { container.start() }
                .onDisappear { container.stop() }
        }
        .defaultSize(width: 1180, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            SettingsView(viewModel: container.settingsViewModel)
                .frame(width: 520, height: 480)
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
}

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

        MenuBarExtra(isInserted: Binding(
            get: { container.settings.showMenuBarExtra },
            set: { container.settings.showMenuBarExtra = $0 }
        )) {
            MenuBarView(container: container)
        } label: {
            MenuBarLabel(container: container)
        }
        .menuBarExtraStyle(.menu)
    }
}

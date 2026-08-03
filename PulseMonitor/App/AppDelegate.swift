import AppKit
import SwiftUI

/// Application delegate.
///
/// PulseMonitor keeps running after its last window is closed — the menu bar
/// item, the overlay and the sampling loop all outlive the UI — so the standard
/// "reopen on Dock click" behaviour has to be wired up explicitly, and the
/// window state macOS restores at launch has to be corrected when it restores
/// nothing at all.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // MenuBarExtra can push the activation policy to .accessory, which then
        // hides ordinary windows. Keep us a regular app so the main window stays
        // first-class alongside the menu bar item.
        NSApp.setActivationPolicy(.regular)
        NSApp.applicationIconImage = BrandArtwork.appIcon
        NSWindow.allowsAutomaticWindowTabbing = true
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")

        if ProcessInfo.processInfo.environment["PULSE_WINDOW_TRACE"] != nil {
            installWindowTrace()
        }

        // Give SwiftUI a beat to materialise the WindowGroup, then reopen if it
        // vanished (a known AppKit quirk when MenuBarExtra coexists with an
        // empty restoration session).
        for delay in [0.0, 0.5, 1.5] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.ensureVisibleWindow()
            }
        }
    }

    nonisolated func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        if !flag {
            MainActor.assumeIsolated { ensureVisibleWindow() }
        }
        return true
    }

    /// Opens a main window when the app has no ordinary window on screen.
    ///
    /// This goes through the File ▸ New menu item rather than `openWindow`
    /// because it has to work when no window exists yet, which is exactly when
    /// no SwiftUI view is around to hand us that environment action.
    func ensureVisibleWindow() {
        NSApp.setActivationPolicy(.regular)

        let candidates = NSApp.windows.filter { window in
            window.canBecomeMain
                && !(window is NSPanel)
                && window.frame.width >= 400
                && window.frame.height >= 300
        }
        if let existing = candidates.first(where: \.isVisible) ?? candidates.first {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        guard let item = newWindowMenuItem(), let action = item.action else { return }
        NSApp.sendAction(action, to: item.target, from: item)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func newWindowMenuItem() -> NSMenuItem? {
        guard let fileMenu = NSApp.mainMenu?.items.first(where: { $0.submenu?.title == "File" })?.submenu
        else { return nil }
        return fileMenu.items.first { $0.action != nil && $0.keyEquivalent == "n" }
    }

    // MARK: - Diagnostics

    private var traceObservers: [NSObjectProtocol] = []

    /// Logs window lifecycle with call stacks. Enabled with `PULSE_WINDOW_TRACE=1`.
    private func installWindowTrace() {
        let centre = NotificationCenter.default
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.willCloseNotification] {
            let token = centre.addObserver(forName: name, object: nil, queue: .main) { note in
                nonisolated(unsafe) let payload = note
                MainActor.assumeIsolated {
                    let window = payload.object as? NSWindow
                    let title = window?.title ?? "nil"
                    let stack = Thread.callStackSymbols.prefix(20).joined(separator: "\n")
                    FileHandle.standardError.write(Data("""
                    [pulse] \(name.rawValue) "\(title)"
                    \(stack)

                    """.utf8))
                }
            }
            traceObservers.append(token)
        }
    }
}

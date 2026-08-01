import Foundation
import AppKit
import CoreAudio
import AudioToolbox

/// Reads and mutates the subset of system settings that macOS exposes to an
/// unprivileged app.
///
/// Controls that would need root, a privileged helper, or a private framework are
/// reported through `descriptors()` with the reason they are unavailable. Nothing
/// here shells out to `sudo` or pretends a change succeeded.
public actor SystemControlService {
    private let capabilityService: CapabilityService

    public init(capabilityService: CapabilityService) {
        self.capabilityService = capabilityService
    }

    // MARK: - Availability

    public func descriptors() async -> [SystemControlDescriptor] {
        let host = await capabilityService.capabilities()
        let audio = Self.defaultOutputDevice() != nil
            ? CapabilityState.supported
            : .unsupported(reason: "No default audio output device is present.")

        let brightness = Self.brightnessState()

        return [
            .init(id: .outputVolume, title: "Output Volume", symbol: "speaker.wave.3.fill", state: audio),
            .init(id: .outputMute, title: "Mute", symbol: "speaker.slash.fill", state: audio),
            .init(id: .appearance, title: "Appearance", symbol: "circle.lefthalf.filled", state: .supported),
            .init(id: .wallpaper, title: "Wallpaper", symbol: "photo.on.rectangle.angled", state: .supported),
            .init(id: .dockAutohide, title: "Auto-hide Dock", symbol: "dock.rectangle", state: .supported),
            .init(id: .dockSize, title: "Dock Size", symbol: "arrow.left.and.right", state: .supported),
            .init(id: .displayBrightness, title: "Display Brightness", symbol: "sun.max.fill", state: brightness),
            .init(
                id: .keyboardBrightness,
                title: "Keyboard Brightness",
                symbol: "keyboard",
                state: .unsupported(reason: "Keyboard backlight is only writable through a private framework.")
            ),
            .init(
                id: .nightShift,
                title: "Night Shift",
                symbol: "moon.fill",
                state: .unsupported(reason: "Night Shift is controlled by the private CoreBrightness framework.")
            ),
            .init(
                id: .trueTone,
                title: "True Tone",
                symbol: "sun.haze.fill",
                state: .unsupported(reason: "True Tone has no public API and is unavailable on this display.")
            ),
            .init(
                id: .doNotDisturb,
                title: "Do Not Disturb",
                symbol: "moon.zzz.fill",
                state: .unsupported(reason: "Focus modes cannot be set programmatically; macOS offers no public API.")
            ),
            .init(
                id: .lowPowerMode,
                title: "Low Power Mode",
                symbol: "battery.25",
                state: host.hasBattery
                    ? .requiresPrivileges(reason: "Changing Low Power Mode requires administrator rights via pmset.")
                    : .unsupported(reason: "This Mac has no battery, so Low Power Mode does not apply.")
            ),
            .init(
                id: .displaySleep,
                title: "Display Sleep",
                symbol: "display",
                state: .requiresPrivileges(reason: "Sleep timings are readable, but changing them requires administrator rights.")
            ),
            .init(
                id: .computerSleep,
                title: "Computer Sleep",
                symbol: "powersleep",
                state: .requiresPrivileges(reason: "Sleep timings are readable, but changing them requires administrator rights.")
            ),
            .init(id: .loginItems, title: "Login Items", symbol: "person.crop.circle.badge.checkmark", state: .supported),
            .init(
                id: .gpuSwitching,
                title: "Automatic Graphics Switching",
                symbol: "rectangle.on.rectangle",
                state: host.isAppleSilicon
                    ? .unsupported(reason: "Apple Silicon has a unified GPU; there is nothing to switch.")
                    : .requiresPrivileges(reason: "Toggling graphics switching requires administrator rights via pmset.")
            )
        ]
    }

    // MARK: - Volume

    public func outputVolume() -> Float? {
        guard let device = Self.defaultOutputDevice() else { return nil }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var volume: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &volume)
        return status == noErr ? volume : nil
    }

    @discardableResult
    public func setOutputVolume(_ value: Float) -> Bool {
        guard let device = Self.defaultOutputDevice() else { return false }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var newValue = Float32(min(1, max(0, value)))
        let size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectSetPropertyData(device, &address, 0, nil, size, &newValue) == noErr
    }

    public func isMuted() -> Bool? {
        guard let device = Self.defaultOutputDevice() else { return nil }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &muted)
        return status == noErr ? muted == 1 : nil
    }

    @discardableResult
    public func setMuted(_ muted: Bool) -> Bool {
        guard let device = Self.defaultOutputDevice() else { return false }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = muted ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectSetPropertyData(device, &address, 0, nil, size, &value) == noErr
    }

    private static func defaultOutputDevice() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device
        )
        return status == noErr && device != 0 ? device : nil
    }

    // MARK: - Appearance

    public func isDarkMode() -> Bool {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle")?.lowercased() == "dark"
    }

    /// Uses the scripting bridge because System Events owns this preference.
    /// Requires the user to grant Automation access on first use.
    @discardableResult
    public func setDarkMode(_ enabled: Bool) -> Result<Void, ControlError> {
        let source = """
        tell application "System Events"
            tell appearance preferences
                set dark mode to \(enabled)
            end tell
        end tell
        """
        return Self.runAppleScript(source)
    }

    // MARK: - Wallpaper

    public func setWallpaper(_ url: URL) -> Result<Void, ControlError> {
        var lastError: Error?
        for screen in NSScreen.screens {
            do {
                try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
            } catch {
                lastError = error
            }
        }
        if let lastError {
            return .failure(.failed(lastError.localizedDescription))
        }
        return .success(())
    }

    // MARK: - Dock

    public func dockAutohide() -> Bool {
        UserDefaults(suiteName: "com.apple.dock")?.bool(forKey: "autohide") ?? false
    }

    public func dockTileSize() -> Double {
        UserDefaults(suiteName: "com.apple.dock")?.double(forKey: "tilesize") ?? 48
    }

    @discardableResult
    public func setDockAutohide(_ enabled: Bool) -> Result<Void, ControlError> {
        Self.writeDockDefault(key: "autohide", value: enabled ? "true" : "false", type: "-bool")
    }

    @discardableResult
    public func setDockTileSize(_ size: Double) -> Result<Void, ControlError> {
        let clamped = Int(min(128, max(16, size)))
        return Self.writeDockDefault(key: "tilesize", value: "\(clamped)", type: "-int")
    }

    private static func writeDockDefault(key: String, value: String, type: String) -> Result<Void, ControlError> {
        let write = Process()
        write.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        write.arguments = ["write", "com.apple.dock", key, type, value]
        do {
            try write.run()
            write.waitUntilExit()
            guard write.terminationStatus == 0 else {
                return .failure(.failed("defaults exited with status \(write.terminationStatus)."))
            }
        } catch {
            return .failure(.failed(error.localizedDescription))
        }

        // The Dock only re-reads its preferences on relaunch.
        let restart = Process()
        restart.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        restart.arguments = ["Dock"]
        try? restart.run()
        restart.waitUntilExit()
        return .success(())
    }

    // MARK: - Brightness

    /// Brightness is only writable on displays whose IOKit service exposes the
    /// brightness parameter, which in practice means Intel built-in panels.
    private static func brightnessState() -> CapabilityState {
        DisplayBrightness.currentBrightness() != nil
            ? .supported
            : .unsupported(reason: "This display does not expose a writable brightness parameter to user space.")
    }

    public func displayBrightness() -> Float? {
        DisplayBrightness.currentBrightness()
    }

    @discardableResult
    public func setDisplayBrightness(_ value: Float) -> Bool {
        DisplayBrightness.setBrightness(min(1, max(0, value)))
    }

    // MARK: - Power settings (read-only)

    /// `pmset -g` is readable without privileges; the matching writes are not,
    /// so this is deliberately query-only.
    public func powerSettingsSummary() -> [String: String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g", "custom"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return [:]
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8) else { return [:] }

        var result: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let parts = line.split(whereSeparator: \.isWhitespace)
            guard parts.count >= 2 else { continue }
            result[String(parts[0])] = String(parts[1])
        }
        return result
    }

    // MARK: - Login items

    public func openLoginItemsSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")
        if let url {
            NSWorkspace.shared.open(url)
        }
    }

    /// Enumerates per-user launch agents, which is what most third-party apps use
    /// to start at login. These are listed for review only; PulseMonitor does not
    /// silently disable them.
    public func userLaunchAgents() -> [LaunchAgent] {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ) else { return [] }

        return entries
            .filter { $0.pathExtension == "plist" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url),
                      let plist = try? PropertyListSerialization.propertyList(
                        from: data, options: [], format: nil
                      ) as? [String: Any] else { return nil }
                return LaunchAgent(
                    label: plist["Label"] as? String ?? url.deletingPathExtension().lastPathComponent,
                    path: url.path,
                    runAtLoad: plist["RunAtLoad"] as? Bool ?? false
                )
            }
            .sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }

    public struct LaunchAgent: Sendable, Identifiable, Equatable {
        public var id: String { path }
        public let label: String
        public let path: String
        public let runAtLoad: Bool
    }

    // MARK: - Helpers

    public enum ControlError: Error, Sendable, Equatable {
        case notPermitted(String)
        case failed(String)

        public var message: String {
            switch self {
            case .notPermitted(let text): text
            case .failed(let text): text
            }
        }
    }

    private static func runAppleScript(_ source: String) -> Result<Void, ControlError> {
        var errorInfo: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            return .failure(.failed("Could not compile the AppleScript command."))
        }
        script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "Unknown AppleScript error."
            let code = errorInfo[NSAppleScript.errorNumber] as? Int ?? 0
            // -1743 is the standard "user has not granted Automation access" code.
            if code == -1743 {
                return .failure(.notPermitted(
                    "PulseMonitor needs Automation access to System Events. Grant it in System Settings › Privacy & Security › Automation."
                ))
            }
            return .failure(.failed(message))
        }
        return .success(())
    }
}

import Foundation
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// Backs the System Control Center and Fan Control screens.
///
/// State is read back from the system after every write so the UI reflects what
/// actually happened rather than what was requested.
@MainActor
@Observable
public final class ControlCenterViewModel {
    public private(set) var descriptors: [SystemControlDescriptor] = []
    public private(set) var host: HostCapabilities = .unknown
    public private(set) var fans: [SMCService.FanReading] = []
    public private(set) var sensors: [SMCService.TemperatureReading] = []
    public private(set) var powerReadings: [SMCService.PowerReading] = []
    public private(set) var launchAgents: [SystemControlService.LaunchAgent] = []
    public private(set) var powerSettings: [String: String] = [:]

    public var volume: Double = 0
    public var isMuted = false
    public var isDarkMode = false
    public var dockAutohide = false
    public var dockSize: Double = 48
    public var brightness: Double = 0

    /// Surfaced verbatim when a write fails, so the user learns the real reason.
    public private(set) var lastError: String?

    private let controlService: SystemControlService
    private let capabilityService: CapabilityService
    private let smcService: SMCService
    private var refreshTask: Task<Void, Never>?
    /// Guards against writing a value back while we are loading it.
    private var isLoading = false

    public init(
        controlService: SystemControlService,
        capabilityService: CapabilityService,
        smcService: SMCService
    ) {
        self.controlService = controlService
        self.capabilityService = capabilityService
        self.smcService = smcService
    }

    public func state(for kind: SystemControlDescriptor.Kind) -> CapabilityState {
        descriptors.first { $0.id == kind }?.state ?? .unsupported(reason: "Not yet determined.")
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }

        host = await capabilityService.capabilities()
        descriptors = await controlService.descriptors()
        launchAgents = await controlService.userLaunchAgents()
        powerSettings = await controlService.powerSettingsSummary()

        if let value = await controlService.outputVolume() { volume = Double(value) }
        if let muted = await controlService.isMuted() { isMuted = muted }
        isDarkMode = await controlService.isDarkMode()
        dockAutohide = await controlService.dockAutohide()
        dockSize = await controlService.dockTileSize()
        if let value = await controlService.displayBrightness() { brightness = Double(value) }

        await refreshSensors()
    }

    /// Polls the SMC while a sensor view is visible.
    public func startSensorPolling(interval: Double = 2.0) {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                await self.refreshSensors()
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    public func stopSensorPolling() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    public func refreshSensors() async {
        guard host.smcAccess.isSupported || host == .unknown else { return }
        fans = await smcService.fans()
        sensors = await smcService.temperatures()
        powerReadings = await smcService.powerReadings()
    }

    // MARK: - Writes

    public func applyVolume(_ value: Double) async {
        guard !isLoading, state(for: .outputVolume).isSupported else { return }
        _ = await controlService.setOutputVolume(Float(value))
        if let actual = await controlService.outputVolume() { volume = Double(actual) }
    }

    public func applyMute(_ muted: Bool) async {
        guard !isLoading, state(for: .outputMute).isSupported else { return }
        _ = await controlService.setMuted(muted)
        if let actual = await controlService.isMuted() { isMuted = actual }
    }

    public func applyBrightness(_ value: Double) async {
        guard !isLoading, state(for: .displayBrightness).isSupported else { return }
        _ = await controlService.setDisplayBrightness(Float(value))
        if let actual = await controlService.displayBrightness() { brightness = Double(actual) }
    }

    public func applyDarkMode(_ enabled: Bool) async {
        guard !isLoading else { return }
        switch await controlService.setDarkMode(enabled) {
        case .success:
            lastError = nil
            isDarkMode = await controlService.isDarkMode()
        case .failure(let error):
            lastError = error.message
            // Snap the toggle back so it never shows a state we did not achieve.
            isDarkMode = await controlService.isDarkMode()
        }
    }

    public func applyDockAutohide(_ enabled: Bool) async {
        guard !isLoading else { return }
        if case .failure(let error) = await controlService.setDockAutohide(enabled) {
            lastError = error.message
        } else {
            lastError = nil
        }
        dockAutohide = await controlService.dockAutohide()
    }

    public func applyDockSize(_ size: Double) async {
        guard !isLoading else { return }
        if case .failure(let error) = await controlService.setDockTileSize(size) {
            lastError = error.message
        } else {
            lastError = nil
        }
        dockSize = await controlService.dockTileSize()
    }

    public func chooseWallpaper() async {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a desktop picture"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        if case .failure(let error) = await controlService.setWallpaper(url) {
            lastError = error.message
        } else {
            lastError = nil
        }
    }

    public func openLoginItems() async {
        await controlService.openLoginItemsSettings()
    }

    public func dismissError() {
        lastError = nil
    }
}

import Foundation

/// Describes whether a given control is actually usable on this machine.
///
/// The app must never present a control it cannot honour, so every mutating
/// feature resolves to one of these states before any UI is shown.
public enum CapabilityState: Sendable, Equatable {
    /// The control works and may be exposed.
    case supported
    /// The hardware or OS forbids it outright; show as disabled with `reason`.
    case unsupported(reason: String)
    /// The mechanism exists but needs privileges this process does not hold.
    case requiresPrivileges(reason: String)

    public var isSupported: Bool {
        if case .supported = self { return true }
        return false
    }

    /// User-facing explanation, or nil when the control is available.
    public var explanation: String? {
        switch self {
        case .supported: nil
        case .unsupported(let reason): reason
        case .requiresPrivileges(let reason): reason
        }
    }
}

/// A single toggleable/adjustable system control and its resolved availability.
public struct SystemControlDescriptor: Sendable, Identifiable, Equatable {
    public let id: Kind
    public let title: String
    public let symbol: String
    public let state: CapabilityState

    public enum Kind: String, Sendable, CaseIterable {
        case outputVolume
        case outputMute
        case appearance
        case wallpaper
        case dockAutohide
        case dockSize
        case displayBrightness
        case keyboardBrightness
        case nightShift
        case trueTone
        case doNotDisturb
        case lowPowerMode
        case displaySleep
        case computerSleep
        case loginItems
        case gpuSwitching
    }

    public init(id: Kind, title: String, symbol: String, state: CapabilityState) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.state = state
    }
}

/// Static description of the host machine used to gate hardware features.
public struct HostCapabilities: Sendable, Equatable {
    public let isAppleSilicon: Bool
    public let modelIdentifier: String
    public let chipName: String
    public let osVersion: String
    public let hasBattery: Bool
    public let fanControl: CapabilityState
    public let fanReadout: CapabilityState
    public let smcAccess: CapabilityState
    public let frameRateOverlay: CapabilityState

    public static let unknown = HostCapabilities(
        isAppleSilicon: false,
        modelIdentifier: "Unknown",
        chipName: "Unknown",
        osVersion: "Unknown",
        hasBattery: false,
        fanControl: .unsupported(reason: "Not yet determined."),
        fanReadout: .unsupported(reason: "Not yet determined."),
        smcAccess: .unsupported(reason: "Not yet determined."),
        frameRateOverlay: .unsupported(reason: "Not yet determined.")
    )
}

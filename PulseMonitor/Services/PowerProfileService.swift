import Foundation

/// A named bundle of monitoring behaviour.
///
/// Profiles only adjust settings PulseMonitor itself owns — polling cadence,
/// thresholds, overlay and notifications. They deliberately do not claim to
/// change OS power settings, because those writes need administrator rights.
public struct PowerProfile: Sendable, Identifiable, Equatable {
    public enum Kind: String, CaseIterable, Identifiable, Codable, Sendable {
        case silent
        case balanced
        case performance
        case gaming
        case videoEditing
        case batterySaver
        case developer

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .silent: "Silent"
            case .balanced: "Balanced"
            case .performance: "Performance"
            case .gaming: "Gaming"
            case .videoEditing: "Video Editing"
            case .batterySaver: "Battery Saver"
            case .developer: "Developer"
            }
        }

        public var symbol: String {
            switch self {
            case .silent: "speaker.slash"
            case .balanced: "scalemass"
            case .performance: "bolt.fill"
            case .gaming: "gamecontroller.fill"
            case .videoEditing: "film.stack"
            case .batterySaver: "battery.25"
            case .developer: "hammer.fill"
            }
        }
    }

    public var id: String { kind.rawValue }
    public let kind: Kind
    public let summary: String
    public let refreshInterval: Double
    public let graphDuration: Double
    public let cpuAlertThreshold: Double
    public let temperatureAlertC: Double
    public let enablesOverlay: Bool
    public let enablesNotifications: Bool

    public static let all: [PowerProfile] = [
        .init(
            kind: .silent,
            summary: "Minimal polling and no alerts. Lowest possible monitoring overhead.",
            refreshInterval: 5.0,
            graphDuration: 300,
            cpuAlertThreshold: 98,
            temperatureAlertC: 100,
            enablesOverlay: false,
            enablesNotifications: false
        ),
        .init(
            kind: .balanced,
            summary: "One-second sampling with standard alert thresholds.",
            refreshInterval: 1.0,
            graphDuration: 60,
            cpuAlertThreshold: 90,
            temperatureAlertC: 95,
            enablesOverlay: false,
            enablesNotifications: true
        ),
        .init(
            kind: .performance,
            summary: "Fast sampling and tight thresholds for spotting short spikes.",
            refreshInterval: 0.5,
            graphDuration: 60,
            cpuAlertThreshold: 85,
            temperatureAlertC: 90,
            enablesOverlay: false,
            enablesNotifications: true
        ),
        .init(
            kind: .gaming,
            summary: "Overlay on, notifications suppressed so nothing interrupts full-screen play.",
            refreshInterval: 0.5,
            graphDuration: 120,
            cpuAlertThreshold: 95,
            temperatureAlertC: 97,
            enablesOverlay: true,
            enablesNotifications: false
        ),
        .init(
            kind: .videoEditing,
            summary: "Longer graphs and thermal-focused alerts for sustained render loads.",
            refreshInterval: 1.0,
            graphDuration: 600,
            cpuAlertThreshold: 95,
            temperatureAlertC: 92,
            enablesOverlay: false,
            enablesNotifications: true
        ),
        .init(
            kind: .batterySaver,
            summary: "Infrequent sampling to keep PulseMonitor's own draw negligible.",
            refreshInterval: 10.0,
            graphDuration: 900,
            cpuAlertThreshold: 95,
            temperatureAlertC: 98,
            enablesOverlay: false,
            enablesNotifications: false
        ),
        .init(
            kind: .developer,
            summary: "Sub-second sampling, long history, and every diagnostic surfaced.",
            refreshInterval: 0.5,
            graphDuration: 300,
            cpuAlertThreshold: 80,
            temperatureAlertC: 88,
            enablesOverlay: true,
            enablesNotifications: true
        )
    ]

    public static func profile(for kind: Kind) -> PowerProfile {
        all.first { $0.kind == kind } ?? all[1]
    }
}

/// Applies profiles to the live settings object.
@MainActor
public final class PowerProfileService {
    private let settings: AppSettings

    public init(settings: AppSettings) {
        self.settings = settings
    }

    public func apply(_ kind: PowerProfile.Kind) {
        let profile = PowerProfile.profile(for: kind)
        settings.refreshIntervalSeconds = profile.refreshInterval
        settings.graphDurationSeconds = profile.graphDuration
        settings.cpuAlertThreshold = profile.cpuAlertThreshold
        settings.temperatureAlertC = profile.temperatureAlertC
        settings.overlayEnabled = profile.enablesOverlay
        settings.notificationsEnabled = profile.enablesNotifications
        settings.activeProfile = kind
    }

    /// True when the live settings still match the profile they came from.
    /// Used to show an "edited" badge instead of silently lying about state.
    public func matchesActiveProfile() -> Bool {
        let profile = PowerProfile.profile(for: settings.activeProfile)
        return settings.refreshIntervalSeconds == profile.refreshInterval
            && settings.graphDurationSeconds == profile.graphDuration
            && settings.cpuAlertThreshold == profile.cpuAlertThreshold
            && settings.temperatureAlertC == profile.temperatureAlertC
    }
}

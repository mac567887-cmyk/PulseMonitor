import SwiftUI

/// The visual identities PulseMonitor ships with.
///
/// A theme only describes colour and material intent. Layout, spacing and motion
/// live in `DesignTokens` so that every theme stays structurally identical.
public enum Theme: String, CaseIterable, Identifiable, Sendable, Codable {
    case apple
    case tahoeDark
    case tahoeLight
    case midnight
    case graphite
    case developer
    case oled
    case classic

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .apple: "Apple"
        case .tahoeDark: "Tahoe Dark"
        case .tahoeLight: "Tahoe Light"
        case .midnight: "Midnight"
        case .graphite: "Graphite"
        case .developer: "Developer"
        case .oled: "OLED"
        case .classic: "Classic"
        }
    }

    /// nil means "follow the system setting".
    public var colorScheme: ColorScheme? {
        switch self {
        case .apple, .classic: nil
        case .tahoeLight: .light
        case .tahoeDark, .midnight, .graphite, .developer, .oled: .dark
        }
    }

    public var accent: Color {
        switch self {
        case .apple: .accentColor
        case .tahoeDark: Color(red: 0.36, green: 0.66, blue: 1.00)
        case .tahoeLight: Color(red: 0.00, green: 0.48, blue: 1.00)
        case .midnight: Color(red: 0.53, green: 0.47, blue: 0.98)
        case .graphite: Color(red: 0.60, green: 0.62, blue: 0.66)
        case .developer: Color(red: 0.20, green: 0.90, blue: 0.55)
        case .oled: Color(red: 0.00, green: 0.85, blue: 0.90)
        case .classic: Color(red: 0.20, green: 0.52, blue: 0.90)
        }
    }

    /// Secondary hue used for gradient sweeps across cards and charts.
    public var secondaryAccent: Color {
        switch self {
        case .apple: Color(red: 0.35, green: 0.34, blue: 0.84)
        case .tahoeDark: Color(red: 0.55, green: 0.40, blue: 0.95)
        case .tahoeLight: Color(red: 0.36, green: 0.30, blue: 0.90)
        case .midnight: Color(red: 0.90, green: 0.40, blue: 0.70)
        case .graphite: Color(red: 0.45, green: 0.47, blue: 0.52)
        case .developer: Color(red: 0.95, green: 0.80, blue: 0.25)
        case .oled: Color(red: 0.35, green: 0.30, blue: 0.95)
        case .classic: Color(red: 0.30, green: 0.65, blue: 0.85)
        }
    }

    /// Material behind cards. OLED deliberately opts out so pixels stay off.
    public var cardMaterial: Material? {
        switch self {
        case .apple, .tahoeDark, .tahoeLight, .midnight: .regularMaterial
        case .graphite, .classic: .thickMaterial
        case .developer: .ultraThinMaterial
        case .oled: nil
        }
    }

    public var usesVibrantBackdrop: Bool {
        switch self {
        case .oled, .classic: false
        default: true
        }
    }

    public var monospacedBody: Bool { self == .developer }
}

/// Shared spacing, radius and motion constants.
///
/// Values are centralised so the whole app changes shape consistently and so no
/// view hardcodes a magic number.
public enum DesignTokens {
    public static let cardCornerRadius: CGFloat = 16
    public static let compactCornerRadius: CGFloat = 10
    public static let cardPadding: CGFloat = 16
    public static let gridSpacing: CGFloat = 14
    public static let sectionSpacing: CGFloat = 20

    /// Corner radius scales with the card so small tiles do not look bulbous.
    public static func adaptiveRadius(for size: CGSize) -> CGFloat {
        let base = min(size.width, size.height)
        return min(24, max(8, base * 0.09))
    }

    public enum Motion {
        /// Primary transition. Spring response is short enough to stay crisp on
        /// 120 Hz panels while remaining smooth at 60 Hz.
        public static let standard = Animation.spring(response: 0.34, dampingFraction: 0.82)
        public static let quick = Animation.spring(response: 0.22, dampingFraction: 0.86)
        public static let gentle = Animation.spring(response: 0.55, dampingFraction: 0.85)
        /// Continuous value changes on charts and gauges.
        public static let value = Animation.easeInOut(duration: 0.28)
    }
}

/// Injects the active theme into the view tree.
public struct ThemeKey: EnvironmentKey {
    public static let defaultValue: Theme = .apple
}

extension EnvironmentValues {
    public var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

import SwiftUI
import AppKit

/// Layered translucent surface used for every card in the app.
///
/// This approximates Tahoe's glass treatment using the materials available in
/// the current SDK: a vibrancy layer, a specular top highlight, a hairline
/// stroke, and a depth shadow that responds to hover.
public struct GlassCardBackground: View {
    public var cornerRadius: CGFloat
    public var isElevated: Bool
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    public init(cornerRadius: CGFloat = DesignTokens.cardCornerRadius, isElevated: Bool = false) {
        self.cornerRadius = cornerRadius
        self.isElevated = isElevated
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        shape
            .fill(fillStyle)
            .overlay {
                // Specular sheen: brighter at the top edge, fading out by the middle.
                shape.fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(colorScheme == .dark ? 0.10 : 0.55),
                            Color.white.opacity(0)
                        ],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
                .blendMode(.plusLighter)
                .opacity(theme == .oled ? 0.25 : 1)
            }
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(colorScheme == .dark ? 0.22 : 0.85),
                            Color.white.opacity(colorScheme == .dark ? 0.04 : 0.25)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
            }
            .shadow(
                color: Color.black.opacity(shadowOpacity),
                radius: isElevated ? 22 : 10,
                y: isElevated ? 12 : 4
            )
    }

    private var fillStyle: AnyShapeStyle {
        if let material = theme.cardMaterial {
            AnyShapeStyle(material)
        } else {
            AnyShapeStyle(Color.black)
        }
    }

    private var shadowOpacity: Double {
        switch theme {
        case .oled: 0
        default: colorScheme == .dark ? (isElevated ? 0.45 : 0.28) : (isElevated ? 0.16 : 0.08)
        }
    }
}

extension View {
    /// Wraps content in the standard glass card treatment.
    public func glassCard(
        cornerRadius: CGFloat = DesignTokens.cardCornerRadius,
        padding: CGFloat = DesignTokens.cardPadding,
        isElevated: Bool = false
    ) -> some View {
        self
            .padding(padding)
            .background(GlassCardBackground(cornerRadius: cornerRadius, isElevated: isElevated))
    }

    /// Applies a hover lift. Used on interactive cards only.
    public func interactiveLift(_ isHovering: Bool) -> some View {
        self
            .scaleEffect(isHovering ? 1.012 : 1)
            .animation(DesignTokens.Motion.quick, value: isHovering)
    }
}

/// Accent gradient wash behind the sidebar and window chrome.
///
/// Static by default. An earlier `repeatForever` version kept the display link
/// running and burned roughly two thirds of main-thread time. When the user
/// explicitly enables “Live backdrop”, a `TimelineView` advances the wash every
/// few seconds — never at display refresh — so the option stays optional and
/// honest about its cost.
public struct AmbientBackdrop: View {
    @Environment(\.theme) private var theme
    @Environment(\.liveBackdropEnabled) private var liveBackdropEnabled

    public init() {}

    public var body: some View {
        if liveBackdropEnabled && theme != .oled {
            // Qualified: the app also defines a Performance Timeline view named TimelineView.
            SwiftUI.TimelineView(.periodic(from: .now, by: 4)) { context in
                layers(phase: context.date.timeIntervalSinceReferenceDate)
            }
        } else {
            layers(phase: 0)
        }
    }

    private func layers(phase: TimeInterval) -> some View {
        GeometryReader { proxy in
            let drift = liveBackdropEnabled ? sin(phase / 12) * 0.04 : 0
            ZStack {
                if theme == .oled {
                    Color.black
                } else {
                    VisualEffectBackdrop(material: .underWindowBackground, blending: .behindWindow)

                    RadialGradient(
                        colors: [theme.accent.opacity(0.22), .clear],
                        center: UnitPoint(x: 0.15 + drift, y: 0.05),
                        startRadius: 0,
                        endRadius: proxy.size.width * 0.75
                    )

                    RadialGradient(
                        colors: [theme.secondaryAccent.opacity(0.18), .clear],
                        center: UnitPoint(x: 0.9 - drift, y: 0.85),
                        startRadius: 0,
                        endRadius: proxy.size.width * 0.7
                    )
                }
            }
            .ignoresSafeArea()
        }
        .allowsHitTesting(false)
    }
}

private struct LiveBackdropKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    public var liveBackdropEnabled: Bool {
        get { self[LiveBackdropKey.self] }
        set { self[LiveBackdropKey.self] = newValue }
    }
}

/// Bridges `NSVisualEffectView` so windows get true behind-window blur, which
/// SwiftUI's `Material` cannot provide on its own.
public struct VisualEffectBackdrop: NSViewRepresentable {
    public var material: NSVisualEffectView.Material
    public var blending: NSVisualEffectView.BlendingMode
    public var isEmphasized: Bool

    public init(
        material: NSVisualEffectView.Material = .sidebar,
        blending: NSVisualEffectView.BlendingMode = .behindWindow,
        isEmphasized: Bool = false
    ) {
        self.material = material
        self.blending = blending
        self.isEmphasized = isEmphasized
    }

    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.state = .followsWindowActiveState
        view.material = material
        view.blendingMode = blending
        view.isEmphasized = isEmphasized
        return view
    }

    public func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blending
        view.isEmphasized = isEmphasized
    }
}

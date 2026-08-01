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

/// Slow-drifting accent gradient used behind the sidebar and window chrome.
///
/// The animation is intentionally long-period so it costs almost nothing per
/// frame while still making the window feel alive.
public struct AmbientBackdrop: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drift: CGFloat = 0

    public init() {}

    public var body: some View {
        GeometryReader { proxy in
            ZStack {
                if theme == .oled {
                    Color.black
                } else {
                    VisualEffectBackdrop(material: .underWindowBackground, blending: .behindWindow)

                    RadialGradient(
                        colors: [theme.accent.opacity(0.22), .clear],
                        center: UnitPoint(x: 0.15 + drift * 0.08, y: 0.05),
                        startRadius: 0,
                        endRadius: proxy.size.width * 0.75
                    )

                    RadialGradient(
                        colors: [theme.secondaryAccent.opacity(0.18), .clear],
                        center: UnitPoint(x: 0.9 - drift * 0.1, y: 0.85),
                        startRadius: 0,
                        endRadius: proxy.size.width * 0.7
                    )
                }
            }
            .ignoresSafeArea()
        }
        .allowsHitTesting(false)
        .onAppear {
            guard !reduceMotion, theme != .oled else { return }
            withAnimation(.easeInOut(duration: 18).repeatForever(autoreverses: true)) {
                drift = 1
            }
        }
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

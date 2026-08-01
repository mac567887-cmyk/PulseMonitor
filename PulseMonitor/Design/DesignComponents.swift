import SwiftUI

/// Radial gauge used for headline metrics.
///
/// The arc animates between values rather than snapping so rapid polling reads
/// as continuous motion instead of flicker.
public struct PulseGauge: View {
    public var value: Double
    public var label: String
    public var caption: String?
    public var tint: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(value: Double, label: String, caption: String? = nil, tint: Color) {
        self.value = value
        self.label = label
        self.caption = caption
        self.tint = tint
    }

    public var body: some View {
        let clamped = min(1, max(0, value))

        ZStack {
            Circle()
                .trim(from: 0, to: 0.78)
                .stroke(
                    Color.primary.opacity(0.10),
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )

            Circle()
                .trim(from: 0, to: 0.78 * clamped)
                .stroke(
                    AngularGradient(
                        colors: [tint.opacity(0.65), tint, tint.opacity(0.85)],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(280)
                    ),
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .shadow(color: tint.opacity(0.45), radius: 6)

            VStack(spacing: 2) {
                Text(label)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                if let caption {
                    Text(caption)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .rotationEffect(.degrees(140))
        .animation(reduceMotion ? nil : DesignTokens.Motion.value, value: clamped)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(caption ?? "Value") \(label)")
    }
}

/// Placeholder shown while a module is waiting for its first sample.
///
/// A sweeping highlight communicates work in progress without implying a value.
public struct ShimmerPlaceholder: View {
    public var height: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    public init(height: CGFloat = 14) {
        self.height = height
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color.primary.opacity(0.08))
            .frame(height: height)
            .overlay {
                GeometryReader { proxy in
                    LinearGradient(
                        colors: [.clear, Color.primary.opacity(0.18), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: proxy.size.width * 0.4)
                    .offset(x: phase * proxy.size.width)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) {
                    phase = 1.6
                }
            }
    }
}

/// Explains why a control is unavailable, sitting directly beneath it.
public struct CapabilityNotice: View {
    public var state: CapabilityState

    public init(state: CapabilityState) {
        self.state = state
    }

    public var body: some View {
        if let explanation = state.explanation {
            Label {
                Text(explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: icon)
                    .foregroundStyle(iconTint)
                    .font(.caption)
            }
            .accessibilityLabel("Unavailable: \(explanation)")
        }
    }

    private var icon: String {
        switch state {
        case .supported: "checkmark.circle"
        case .unsupported: "lock.circle"
        case .requiresPrivileges: "key.horizontal"
        }
    }

    private var iconTint: Color {
        switch state {
        case .supported: .green
        case .unsupported: .secondary
        case .requiresPrivileges: .orange
        }
    }
}

/// Section container with a title, optional trailing accessory, and glass body.
public struct GlassSection<Content: View, Accessory: View>: View {
    public var title: String
    public var systemImage: String?
    @ViewBuilder public var content: () -> Content
    @ViewBuilder public var accessory: () -> Accessory

    public init(
        title: String,
        systemImage: String? = nil,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder accessory: @escaping () -> Accessory = { EmptyView() }
    ) {
        self.title = title
        self.systemImage = systemImage
        self.content = content
        self.accessory = accessory
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .foregroundStyle(.secondary)
                }
                Text(title)
                    .font(.headline)
                Spacer(minLength: 8)
                accessory()
            }
            content()
        }
        .glassCard()
    }
}

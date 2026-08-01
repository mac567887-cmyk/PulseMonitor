import SwiftUI
import AppKit

/// Contents of the floating performance overlay.
///
/// Frame rate is deliberately absent: measuring another application's frame rate
/// needs private APIs or Metal's own HUD, so PulseMonitor shows only values it
/// can actually read.
public struct PerformanceOverlayContent: View {
    let viewModel: OverlayViewModel
    @Bindable var settings: AppSettings

    public init(viewModel: OverlayViewModel, settings: AppSettings) {
        self.viewModel = viewModel
        self.settings = settings
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(viewModel.enabledMetrics) { metric in
                HStack(spacing: 8) {
                    Text(metric.displayName)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(width: 52, alignment: .leading)

                    Text(viewModel.value(for: metric))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(tint(for: metric))
                        .frame(minWidth: 58, alignment: .trailing)
                }
            }

            if viewModel.enabledMetrics.isEmpty {
                Text("No metrics selected")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.8)
                }
        }
        .opacity(settings.overlayOpacity)
        .animation(DesignTokens.Motion.value, value: viewModel.metrics?.timestamp)
        .fixedSize()
    }

    private func tint(for metric: AppSettings.OverlayMetric) -> Color {
        guard let fraction = viewModel.fraction(for: metric) else {
            return Color(hex: settings.overlayTintHex) ?? .primary
        }
        switch fraction {
        case ..<0.6: return Color(hex: settings.overlayTintHex) ?? .primary
        case ..<0.85: return .orange
        default: return .red
        }
    }
}

/// Borderless panel that hosts the overlay.
///
/// Uses `NSPanel` with a non-activating style so clicking the overlay never
/// steals focus from a full-screen game, and joins all Spaces so it stays
/// visible when the user switches desktops.
@MainActor
public final class OverlayWindowController {
    private var panel: NSPanel?
    private let viewModel: OverlayViewModel
    private let settings: AppSettings

    public init(viewModel: OverlayViewModel, settings: AppSettings) {
        self.viewModel = viewModel
        self.settings = settings
    }

    public func show() {
        if let panel {
            applyLevel(to: panel)
            panel.orderFrontRegardless()
            return
        }

        let hosting = NSHostingController(
            rootView: PerformanceOverlayContent(viewModel: viewModel, settings: settings)
        )

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 160, height: 110),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hosting
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        applyLevel(to: panel)

        // Park it in the top-right of the main display on first appearance.
        if let screen = NSScreen.main {
            let size = hosting.view.fittingSize
            panel.setFrame(
                NSRect(
                    x: screen.visibleFrame.maxX - size.width - 24,
                    y: screen.visibleFrame.maxY - size.height - 24,
                    width: max(size.width, 140),
                    height: max(size.height, 60)
                ),
                display: true
            )
        }

        panel.orderFrontRegardless()
        self.panel = panel
    }

    public func hide() {
        panel?.orderOut(nil)
        panel = nil
    }

    /// Reapplies window level and click-through when the user changes settings.
    public func refresh() {
        guard let panel else { return }
        applyLevel(to: panel)
    }

    private func applyLevel(to panel: NSPanel) {
        // Game mode raises the panel above full-screen content and makes it
        // click-through so it cannot interfere with play.
        if settings.overlayGameMode {
            panel.level = .screenSaver
            panel.ignoresMouseEvents = true
        } else if settings.overlayAlwaysOnTop {
            panel.level = .floating
            panel.ignoresMouseEvents = false
        } else {
            panel.level = .normal
            panel.ignoresMouseEvents = false
        }
    }
}

extension Color {
    /// Parses `#RRGGBB`. Returns nil for anything else so callers can fall back.
    public init?(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let number = UInt32(value, radix: 16) else { return nil }
        self.init(
            red: Double((number >> 16) & 0xFF) / 255,
            green: Double((number >> 8) & 0xFF) / 255,
            blue: Double(number & 0xFF) / 255
        )
    }

    /// Serialises back to `#RRGGBB` for persistence.
    public var hexString: String {
        let color = NSColor(self).usingColorSpace(.sRGB) ?? .white
        return String(
            format: "#%02X%02X%02X",
            Int(round(color.redComponent * 255)),
            Int(round(color.greenComponent * 255)),
            Int(round(color.blueComponent * 255))
        )
    }
}

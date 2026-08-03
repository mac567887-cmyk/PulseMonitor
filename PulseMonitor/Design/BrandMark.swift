import AppKit
import SwiftUI

/// Loads the PulseMonitor brand artwork shipped in the app bundle.
@MainActor
public enum BrandArtwork {
    /// Dock / Finder icon, or the logo PNG when the icns is unavailable.
    public static var appIcon: NSImage {
        if let named = NSImage(named: "AppIcon"), named.size.width > 0 {
            return named
        }
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return logo
    }

    /// In-app logo mark (PNG in `Contents/Resources`).
    public static var logo: NSImage {
        logoImage(named: "AppLogo")
            ?? logoImage(named: "AppLogo128")
            ?? placeholder
    }

    private static func logoImage(named name: String) -> NSImage? {
        if let image = NSImage(named: name), image.size.width > 0 { return image }
        if let url = Bundle.main.url(forResource: name, withExtension: "png") {
            return NSImage(contentsOf: url)
        }
        // SPM debug runs without the .app wrapper; fall back to the source tree.
        let candidates = [
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Resources/\(name).png"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("PulseMonitor/Resources/\(name).png")
        ]
        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            if let image = NSImage(contentsOf: url) { return image }
        }
        return nil
    }

    private static var placeholder: NSImage {
        let image = NSImage(size: NSSize(width: 256, height: 256))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: 256, height: 256), xRadius: 56, yRadius: 56).fill()
        image.unlockFocus()
        return image
    }
}

/// Rounded brand mark used in the dashboard header, sidebar and About surfaces.
public struct BrandMark: View {
    public var size: CGFloat
    public var cornerRadius: CGFloat?

    public init(size: CGFloat = 44, cornerRadius: CGFloat? = nil) {
        self.size = size
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        Image(nsImage: BrandArtwork.logo)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius ?? size * 0.22, style: .continuous))
            .accessibilityLabel("PulseMonitor")
    }
}

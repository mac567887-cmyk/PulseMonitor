import AppKit
import Foundation
import Observation

/// Optional desktop wallpaper slideshow and in-app live backdrop control.
///
/// The in-app “live” backdrop is deliberately slow (a few seconds per phase)
/// so enabling it never returns the app to a continuous 120 Hz redraw. Desktop
/// rotation uses `NSWorkspace.setDesktopImageURL`, the same public API System
/// Settings uses.
@MainActor
@Observable
public final class LiveWallpaperService {
    public private(set) var folderURL: URL?
    public private(set) var imageURLs: [URL] = []
    public private(set) var currentIndex: Int = 0
    public private(set) var statusMessage: String?
    public var isRotating = false

    private var rotationTask: Task<Void, Never>?
    private let defaults: UserDefaults

    private enum Keys {
        static let folder = "liveWallpaper.folderBookmark"
        static let interval = "liveWallpaper.intervalSeconds"
        static let liveBackdrop = "liveWallpaper.liveBackdropEnabled"
    }

    public var intervalSeconds: Double {
        didSet {
            guard oldValue != intervalSeconds else { return }
            defaults.set(intervalSeconds, forKey: Keys.interval)
            if isRotating { startRotation() }
        }
    }

    /// When true, AmbientBackdrop uses a slow TimelineView shimmer.
    public var liveBackdropEnabled: Bool {
        didSet {
            guard oldValue != liveBackdropEnabled else { return }
            defaults.set(liveBackdropEnabled, forKey: Keys.liveBackdrop)
        }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.intervalSeconds = defaults.object(forKey: Keys.interval) as? Double ?? 120
        self.liveBackdropEnabled = defaults.object(forKey: Keys.liveBackdrop) as? Bool ?? false
        if let data = defaults.data(forKey: Keys.folder) {
            var stale = false
            if let url = try? URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) {
                folderURL = url
                reloadImages()
            }
        }
    }

    public func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder of images to rotate as desktop wallpaper."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        folderURL = url
        if let bookmark = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            defaults.set(bookmark, forKey: Keys.folder)
        }
        reloadImages()
        statusMessage = "\(imageURLs.count) images found."
    }

    public func reloadImages() {
        guard let folderURL else {
            imageURLs = []
            return
        }
        _ = folderURL.startAccessingSecurityScopedResource()
        let allowed: Set<String> = ["png", "jpg", "jpeg", "heic", "tif", "tiff"]
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        imageURLs = urls
            .filter { allowed.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
        currentIndex = min(currentIndex, max(imageURLs.count &- 1, 0))
    }

    public func applyCurrent() {
        guard imageURLs.indices.contains(currentIndex) else {
            statusMessage = "No wallpaper images available."
            return
        }
        do {
            guard let screen = NSScreen.main else {
                statusMessage = "No display available."
                return
            }
            try NSWorkspace.shared.setDesktopImageURL(imageURLs[currentIndex], for: screen, options: [:])
            statusMessage = "Desktop set to \(imageURLs[currentIndex].lastPathComponent)"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    public func startRotation() {
        stopRotation()
        guard !imageURLs.isEmpty else {
            statusMessage = "Choose a folder with images first."
            return
        }
        isRotating = true
        rotationTask = Task { [weak self] in
            while let self, !Task.isCancelled, self.isRotating {
                self.applyCurrent()
                self.currentIndex = (self.currentIndex + 1) % max(self.imageURLs.count, 1)
                let nanos = UInt64(max(15, self.intervalSeconds) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanos)
            }
        }
    }

    public func stopRotation() {
        isRotating = false
        rotationTask?.cancel()
        rotationTask = nil
    }
}

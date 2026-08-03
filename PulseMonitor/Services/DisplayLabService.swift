import AppKit
import CoreGraphics
import Foundation
import Observation

public struct DisplayInfo: Sendable, Identifiable, Equatable {
    public var id: String
    public let name: String
    public let widthPoints: Double
    public let heightPoints: Double
    public let widthPixels: Double
    public let heightPixels: Double
    public let scale: Double
    public let refreshHz: Int
    public let backingStoreDepth: Int?
    public let isMain: Bool
    public let isBuiltin: Bool
    public let colorSpaceName: String?
}

@MainActor
@Observable
public final class DisplayLabService {
    public private(set) var displays: [DisplayInfo] = []
    public private(set) var lastRefreshChange: String?
    private var previousRefresh: [String: Int] = [:]

    public init() {}

    public func refresh() {
        var next: [DisplayInfo] = []
        for (index, screen) in NSScreen.screens.enumerated() {
            let scale = screen.backingScaleFactor
            let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                .flatMap { "\($0)" } ?? "screen-\(index)"
            let colorSpace = screen.colorSpace?.localizedName
            let info = DisplayInfo(
                id: id,
                name: screen.localizedName,
                widthPoints: screen.frame.width,
                heightPoints: screen.frame.height,
                widthPixels: screen.frame.width * scale,
                heightPixels: screen.frame.height * scale,
                scale: scale,
                refreshHz: Int(screen.maximumFramesPerSecond),
                backingStoreDepth: Int(screen.depth.rawValue),
                isMain: screen == NSScreen.main,
                isBuiltin: screen.localizedName.localizedCaseInsensitiveContains("built"),
                colorSpaceName: colorSpace
            )
            if let old = previousRefresh[id], old != info.refreshHz {
                lastRefreshChange = "\(info.name) changed \(old) → \(info.refreshHz) Hz"
            }
            previousRefresh[id] = info.refreshHz
            next.append(info)
        }
        displays = next
    }
}

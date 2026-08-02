import Foundation
import Observation

@MainActor
@Observable
public final class SettingsViewModel {
    public var settings: AppSettings
    public var liveWallpaper: LiveWallpaperService

    public init(settings: AppSettings, liveWallpaper: LiveWallpaperService) {
        self.settings = settings
        self.liveWallpaper = liveWallpaper
    }
}

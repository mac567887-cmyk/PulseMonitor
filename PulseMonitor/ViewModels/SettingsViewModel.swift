import Foundation
import Observation

@MainActor
@Observable
public final class SettingsViewModel {
    public var settings: AppSettings
    public init(settings: AppSettings) { self.settings = settings }
}

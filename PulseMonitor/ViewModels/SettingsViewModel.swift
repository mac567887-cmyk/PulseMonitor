import Foundation
import Observation

@MainActor
@Observable
public final class SettingsViewModel {
    public let settings: AppSettings
    public init(settings: AppSettings) { self.settings = settings }
}

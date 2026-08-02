import Foundation

/// Process-wide handle so App Intents and menu-bar actions can reach the live
/// dependency graph without creating a second collector.
@MainActor
public enum SharedAppContext {
    public private(set) static var container: AppContainer?

    public static func bind(_ container: AppContainer) {
        self.container = container
    }
}

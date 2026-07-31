import Foundation
import Observation

@MainActor
@Observable
public final class HistoryViewModel {
    public let historyRepository: HistoryRepository
    public var settings: AppSettings
    public var points: [HistoryRepository.HistoryPoint] = []
    public var selectedRetention: HistoryRetention

    public init(historyRepository: HistoryRepository, settings: AppSettings) {
        self.historyRepository = historyRepository
        self.settings = settings
        self.selectedRetention = settings.historyRetention
    }

    public func reload() {
        Task {
            let seconds = selectedRetention.seconds
            points = await historyRepository.recent(seconds: min(seconds, settings.graphDurationSeconds * 60))
        }
    }
}

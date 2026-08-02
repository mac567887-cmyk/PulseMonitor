import Foundation
import Observation

@MainActor
@Observable
public final class ProcessViewModel {
    public let collector: MetricsCollector
    public let processService: ProcessService

    public var searchText = ""
    public var sortColumn: SortColumn = .cpu
    public var sortAscending = false
    public var showTree = false

    public enum SortColumn: String, CaseIterable, Identifiable {
        case cpu, memory, threads, pid, name
        public var id: String { rawValue }
    }

    /// How many of the machine's processes this app is allowed to inspect.
    public private(set) var coverage = ProcessService.Coverage(visible: 0, total: 0)

    public init(collector: MetricsCollector, processService: ProcessService) {
        self.collector = collector
        self.processService = processService
    }

    public func refreshCoverage() async {
        coverage = await processService.coverage
    }

    public var processes: [ProcessInfoModel] {
        var items = collector.latestProcesses
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            items = items.filter {
                $0.name.lowercased().contains(q)
                || ($0.bundleIdentifier?.lowercased().contains(q) ?? false)
                || String($0.pid).contains(q)
            }
        }
        items.sort { lhs, rhs in
            let result: Bool
            switch sortColumn {
            case .cpu: result = lhs.cpuPercent < rhs.cpuPercent
            case .memory: result = lhs.memoryBytes < rhs.memoryBytes
            case .threads: result = lhs.threadCount < rhs.threadCount
            case .pid: result = lhs.pid < rhs.pid
            case .name: result = lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            return sortAscending ? result : !result
        }
        return items
    }

    public func kill(_ process: ProcessInfoModel, force: Bool = false) {
        Task { _ = await processService.kill(pid: process.pid, force: force) }
    }

    public func reveal(_ process: ProcessInfoModel) {
        guard let path = process.executablePath else { return }
        processService.revealInFinder(path: path)
    }
}

import SwiftUI
import AppKit

public struct ProcessExplorerView: View {
    @Bindable var viewModel: ProcessViewModel
    @State private var selection: Set<ProcessInfoModel.ID> = []

    public var body: some View {
        VStack(spacing: 0) {
            toolbar
            Table(viewModel.processes, selection: $selection) {
                TableColumn("PID") { (proc: ProcessInfoModel) in
                    Text("\(proc.pid)").monospacedDigit()
                }
                .width(60)
                TableColumn("Name") { (proc: ProcessInfoModel) in
                    HStack {
                        Text(proc.name)
                        if proc.isGame {
                            Image(systemName: "gamecontroller.fill").foregroundStyle(.orange)
                        }
                    }
                }
                .width(min: 140, ideal: 200)
                TableColumn("CPU") { (proc: ProcessInfoModel) in
                    Text(Formatters.percent(proc.cpuPercent, digits: 1)).monospacedDigit()
                }
                .width(70)
                TableColumn("Memory") { (proc: ProcessInfoModel) in
                    Text(Formatters.bytes(proc.memoryBytes))
                }
                .width(90)
                TableColumn("Threads") { (proc: ProcessInfoModel) in
                    Text("\(proc.threadCount)").monospacedDigit()
                }
                .width(70)
                TableColumn("Arch") { (proc: ProcessInfoModel) in
                    Text(proc.architecture)
                }
                .width(110)
                TableColumn("Developer") { (proc: ProcessInfoModel) in
                    Text(proc.developer ?? "—")
                }
                .width(100)
                TableColumn("Signature") { (proc: ProcessInfoModel) in
                    Text(proc.codeSignatureStatus)
                }
                .width(80)
                TableColumn("Path") { (proc: ProcessInfoModel) in
                    Text(proc.executablePath ?? "—")
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                }
            }
            .contextMenu {
                if let id = selection.first, let proc = viewModel.processes.first(where: { $0.id == id }) {
                    Button("Reveal in Finder") { viewModel.reveal(proc) }
                    Button("Open Binary") {
                        if let path = proc.executablePath {
                            NSWorkspace.shared.open(URL(fileURLWithPath: path))
                        }
                    }
                    Divider()
                    Button("Quit Process", role: .destructive) { viewModel.kill(proc) }
                    Button("Force Quit", role: .destructive) { viewModel.kill(proc, force: true) }
                }
            }
        }
        .background(AmbientBackground())
    }

    private var toolbar: some View {
        HStack {
            TextField("Search processes", text: $viewModel.searchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 280)
            Picker("Sort", selection: $viewModel.sortColumn) {
                ForEach(ProcessViewModel.SortColumn.allCases) { col in
                    Text(col.rawValue.capitalized).tag(col)
                }
            }
            .frame(width: 140)
            Toggle("Ascending", isOn: $viewModel.sortAscending).toggleStyle(.checkbox)
            Spacer()
            coverageLabel
        }
        .padding(12)
        .task(id: viewModel.processes.count) { await viewModel.refreshCoverage() }
    }

    /// States plainly how much of the process table is visible. `proc_pidinfo`
    /// only answers for processes owned by this user, so a list that silently
    /// omitted the rest would misrepresent what is running.
    private var coverageLabel: some View {
        let coverage = viewModel.coverage
        return HStack(spacing: 6) {
            Text("\(viewModel.processes.count) processes")
            if !coverage.isComplete, coverage.total > 0 {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                    .help(
                        "\(coverage.total - coverage.visible) of \(coverage.total) processes belong to other users. "
                        + "macOS does not allow reading their CPU or memory without running as root, so they are not listed."
                    )
            }
        }
        .foregroundStyle(.secondary)
    }
}

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
                TableColumn("Energy") { (proc: ProcessInfoModel) in
                    Text(String(format: "%.1f", proc.energyImpact ?? 0)).monospacedDigit()
                }
                .width(70)
                TableColumn("Arch") { (proc: ProcessInfoModel) in
                    Text(proc.architecture)
                }
                .width(60)
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
            Text("\(viewModel.processes.count) processes")
                .foregroundStyle(.secondary)
        }
        .padding(12)
    }
}

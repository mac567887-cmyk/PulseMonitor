import SwiftUI
import AppKit

/// Application Manager.
///
/// Architecture comes from reading each bundle's Mach-O header, and the
/// developer name from the code signature, so both reflect the binary on disk
/// rather than a guess from the bundle identifier.
public struct AppManagerView: View {
    @Bindable var viewModel: AppManagerViewModel
    @State private var selection: InstalledApp?
    @State private var pendingTrash: InstalledApp?

    public init(viewModel: AppManagerViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        HSplitView {
            listPane
                .frame(minWidth: 320, idealWidth: 400)

            if let selection {
                InspectorPane(app: selection, viewModel: viewModel) {
                    pendingTrash = selection
                }
                .frame(minWidth: 300)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 34))
                        .foregroundStyle(.tertiary)
                    Text("Select an application")
                        .foregroundStyle(.secondary)
                }
                .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(AmbientBackdrop())
        .navigationTitle("Applications")
        .task { if viewModel.apps.isEmpty { await viewModel.load() } }
        .animation(DesignTokens.Motion.standard, value: selection)
        .confirmationDialog(
            "Move \(pendingTrash?.name ?? "") to the Trash?",
            isPresented: Binding(
                get: { pendingTrash != nil },
                set: { if !$0 { pendingTrash = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) {
                if let app = pendingTrash {
                    Task {
                        await viewModel.moveToTrash(app)
                        selection = nil
                    }
                }
                pendingTrash = nil
            }
            Button("Cancel", role: .cancel) { pendingTrash = nil }
        } message: {
            Text("The application moves to the Trash and can be restored from there. Its preferences and container are left in place.")
        }
        .alert(
            "Could not complete that",
            isPresented: Binding(
                get: { viewModel.actionError != nil },
                set: { if !$0 { viewModel.dismissError() } }
            )
        ) {
            Button("OK") { viewModel.dismissError() }
        } message: {
            Text(viewModel.actionError ?? "")
        }
    }

    private var listPane: some View {
        VStack(spacing: 0) {
            filterBar

            if viewModel.isLoading {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Reading application bundles…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(viewModel.filtered, selection: $selection) { app in
                    row(app)
                        .tag(app)
                }
                .listStyle(.inset)
            }
        }
    }

    private var filterBar: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search applications", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                if !viewModel.searchText.isEmpty {
                    Button {
                        viewModel.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06))
            )

            HStack(spacing: 6) {
                filterChip(nil, label: "All \(viewModel.apps.count)")
                ForEach([BinaryArchitecture.universal, .appleSilicon, .intel], id: \.rawValue) { architecture in
                    let count = viewModel.architectureCounts[architecture] ?? 0
                    if count > 0 {
                        filterChip(architecture, label: "\(architecture.rawValue) \(count)")
                    }
                }
                Spacer()
                Button {
                    Task { await viewModel.load(forceRefresh: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Rescan applications")
            }
        }
        .padding(10)
    }

    private func filterChip(_ architecture: BinaryArchitecture?, label: String) -> some View {
        let isActive = viewModel.architectureFilter == architecture

        return Button {
            withAnimation(DesignTokens.Motion.quick) {
                viewModel.architectureFilter = isActive ? nil : architecture
            }
        } label: {
            Text(label)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(isActive ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.06))
                )
                .foregroundStyle(isActive ? Color.accentColor : .secondary)
        }
        .buttonStyle(.plain)
    }

    private func row(_ app: InstalledApp) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.bundlePath))
                .resizable()
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(app.name).lineLimit(1)
                HStack(spacing: 5) {
                    if let version = app.version {
                        Text(version)
                    }
                    if let developer = app.developer {
                        Text("· \(developer)").lineLimit(1).truncationMode(.tail)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 6)

            Label(app.architecture.rawValue, systemImage: app.architecture.symbol)
                .font(.caption2)
                .labelStyle(.iconOnly)
                .foregroundStyle(.tertiary)
                .help(app.architecture.rawValue)
        }
        .padding(.vertical, 2)
    }
}

/// Detail pane for one application.
private struct InspectorPane: View {
    let app: InstalledApp
    let viewModel: AppManagerViewModel
    let onTrash: () -> Void

    @State private var runningCount = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.gridSpacing) {
                identity
                actions
                details
                permissions
                crashes
            }
            .padding(DesignTokens.sectionSpacing)
        }
        .onAppear { refreshRunning() }
        .onChange(of: app) { _, _ in refreshRunning() }
    }

    private var identity: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.bundlePath))
                .resizable()
                .frame(width: 60, height: 60)

            VStack(alignment: .leading, spacing: 3) {
                Text(app.name).font(.title2.weight(.semibold))
                if let developer = app.developer {
                    Text(developer).font(.callout).foregroundStyle(.secondary)
                }
                Label(app.architecture.rawValue, systemImage: app.architecture.symbol)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .glassCard()
    }

    private var actions: some View {
        GlassSection(title: "Actions", systemImage: "bolt.horizontal") {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Button {
                        AppManagerService.launch(app)
                        // Give launchd a moment before re-reading the state.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { refreshRunning() }
                    } label: {
                        Label("Launch", systemImage: "play.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        AppManagerService.forceQuit(app)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { refreshRunning() }
                    } label: {
                        Label("Force Quit", systemImage: "xmark.octagon").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                    .disabled(runningCount == 0)
                    .help(runningCount == 0 ? "This application is not running." : "Terminate \(runningCount) running instance(s)")
                }

                HStack(spacing: 8) {
                    Button {
                        AppManagerService.reveal(app)
                    } label: {
                        Label("Reveal", systemImage: "folder").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        if let url = viewModel.containerURL(for: app) {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Label("Container", systemImage: "shippingbox").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.containerURL(for: app) == nil)
                    .help(viewModel.containerURL(for: app) == nil ? "This app is not sandboxed, so it has no container." : "")
                }

                HStack(spacing: 8) {
                    Button {
                        if let url = viewModel.preferencesURL(for: app) {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                    } label: {
                        Label("Preferences", systemImage: "gearshape").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.preferencesURL(for: app) == nil)

                    Button(role: .destructive, action: onTrash) {
                        Label("Move to Trash", systemImage: "trash").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }

                if runningCount > 0 {
                    Label("\(runningCount) instance\(runningCount == 1 ? "" : "s") running", systemImage: "circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var details: some View {
        GlassSection(title: "Details", systemImage: "info.circle") {
            VStack(spacing: 6) {
                detailRow("Version", app.version ?? "—")
                detailRow("Build", app.buildNumber ?? "—")
                detailRow("Bundle ID", app.bundleIdentifier ?? "—")
                detailRow("Architecture", app.architecture.rawValue)
                if let minimum = app.minimumSystemVersion {
                    detailRow("Requires macOS", minimum)
                }
                if let size = app.sizeBytes, size > 0 {
                    detailRow("Bundle size", Formatters.bytes(UInt64(size)))
                }
                if let modified = app.lastModified {
                    detailRow("Modified", modified.formatted(date: .abbreviated, time: .omitted))
                }
                detailRow("Path", app.bundlePath)
            }
        }
    }

    private var permissions: some View {
        let declared = viewModel.permissions(for: app)

        return GlassSection(title: "Declared Permissions", systemImage: "hand.raised") {
            VStack(alignment: .leading, spacing: 8) {
                if declared.isEmpty {
                    Text("This app declares no privacy usage descriptions.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(declared, id: \.key) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.key).font(.caption.weight(.medium))
                            Text(entry.description)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                Text("This is what the app asks for. Whether you granted it lives in a protected database that no app can read, so PulseMonitor cannot show the answer.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var crashes: some View {
        let reports = viewModel.crashReports(for: app)

        return GlassSection(title: "Crash History", systemImage: "exclamationmark.triangle") {
            VStack(alignment: .leading, spacing: 6) {
                if reports.isEmpty {
                    Text("No crash reports on file for this application.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(reports.prefix(8)) { report in
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: report.path)])
                        } label: {
                            HStack {
                                Image(systemName: "doc.text").foregroundStyle(.orange)
                                Text(report.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                Spacer()
                                Image(systemName: "arrow.up.forward.square").font(.caption2)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    if reports.count > 8 {
                        Text("and \(reports.count - 8) older reports")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func refreshRunning() {
        runningCount = AppManagerService.runningInstances(of: app).count
    }
}

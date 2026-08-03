import Charts
import SceneKit
import SwiftUI

// MARK: - Health Score

public struct HealthScoreView: View {
    let report: HealthScoreReport?
    let history: [HealthScoreReport]

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .firstTextBaseline) {
                    Text(String(format: "%.0f", report?.overall ?? 100))
                        .font(.system(size: 64, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("/ 100")
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let delta = report?.delta {
                        Text(String(format: "%+.0f", delta))
                            .foregroundStyle(delta >= 0 ? .green : .orange)
                            .font(.title2.weight(.semibold))
                    }
                }
                .glassCard()

                if let reasons = report?.changeReasons, !reasons.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Why it changed").font(.headline)
                        ForEach(reasons, id: \.self) { Text("• \($0)").foregroundStyle(.secondary) }
                    }
                    .glassCard()
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                    ForEach(report?.categories ?? []) { category in
                        VStack(alignment: .leading, spacing: 6) {
                            Label(category.category.displayName, systemImage: category.category.symbol)
                                .font(.subheadline.weight(.semibold))
                            Text(category.available ? String(format: "%.0f", category.score) : "—")
                                .font(.title.weight(.bold))
                                .monospacedDigit()
                            Text(category.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .glassCard()
                    }
                }

                if history.count > 1 {
                    Chart(history.suffix(48), id: \.timestamp) { point in
                        LineMark(
                            x: .value("Time", point.timestamp),
                            y: .value("Score", point.overall)
                        )
                        .foregroundStyle(Color.accentColor)
                    }
                    .frame(height: 180)
                    .glassCard()
                }
            }
            .padding(20)
        }
        .background(AmbientBackdrop())
        .navigationTitle("Health Score")
    }
}

// MARK: - Digital Twin / 3D Map

public struct DigitalTwinView: View {
    let twin: DigitalTwinState?
    @State private var selected: TwinComponent.Kind?

    public var body: some View {
        HSplitView {
            SystemSceneView(twin: twin, selected: $selected)
                .frame(minWidth: 420, minHeight: 420)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Inspector").font(.title2.weight(.semibold))
                    if let component = twin?.components.first(where: { $0.kind == selected }) ?? twin?.components.first {
                        componentCard(component)
                    }
                    Text("Predictions").font(.headline)
                    ForEach(twin?.predictions ?? []) { prediction in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(prediction.title).font(.subheadline.weight(.semibold))
                                if prediction.isEstimate {
                                    Text("Estimate")
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(.orange.opacity(0.2), in: Capsule())
                                }
                            }
                            Text(prediction.detail).foregroundStyle(.secondary).font(.callout)
                            Text(String(format: "Confidence %.0f%%", prediction.confidence * 100))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .glassCard()
                    }
                }
                .padding()
            }
            .frame(minWidth: 280)
        }
        .background(AmbientBackdrop())
        .navigationTitle("Digital Twin")
    }

    private func componentCard(_ component: TwinComponent) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(component.kind.displayName).font(.title3.weight(.semibold))
            if component.available {
                if let load = component.load { LabeledContent("Load", value: Formatters.percent(load)) }
                if let temp = component.temperatureC { LabeledContent("Temperature", value: Formatters.celsius(temp)) }
                if let power = component.powerWatts { LabeledContent("Power", value: Formatters.watts(power)) }
                if let health = component.health { LabeledContent("Health", value: Formatters.percent(health)) }
            } else {
                Text(component.unavailableReason ?? "Unavailable")
                    .foregroundStyle(.secondary)
            }
        }
        .glassCard()
    }
}

/// Lightweight SceneKit visualization — colours update from the digital twin heat value.
public struct SystemSceneView: NSViewRepresentable {
    let twin: DigitalTwinState?
    @Binding var selected: TwinComponent.Kind?

    public func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = makeScene()
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = true
        view.backgroundColor = .clear
        let click = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.clicked(_:)))
        view.addGestureRecognizer(click)
        context.coordinator.view = view
        return view
    }

    public func updateNSView(_ view: SCNView, context: Context) {
        guard let scene = view.scene else { return }
        for component in twin?.components ?? [] {
            guard let node = scene.rootNode.childNode(withName: component.kind.rawValue, recursively: true) else { continue }
            let heat = component.available ? component.heat : 0.05
            let color = NSColor(
                hue: 0.6 - (0.55 * heat),
                saturation: component.available ? 0.85 : 0.1,
                brightness: 0.95,
                alpha: 1
            )
            node.geometry?.firstMaterial?.diffuse.contents = color
            node.geometry?.firstMaterial?.emission.contents = color.withAlphaComponent(0.25 * heat)
        }
    }

    public func makeCoordinator() -> Coordinator { Coordinator(selected: $selected) }

    @MainActor
    public final class Coordinator: NSObject {
        var selected: Binding<TwinComponent.Kind?>
        weak var view: SCNView?
        init(selected: Binding<TwinComponent.Kind?>) { self.selected = selected }

        @objc func clicked(_ gesture: NSClickGestureRecognizer) {
            guard let view else { return }
            let point = gesture.location(in: view)
            let hits = view.hitTest(point, options: nil)
            if let name = hits.first?.node.name, let kind = TwinComponent.Kind(rawValue: name) {
                selected.wrappedValue = kind
            }
        }
    }

    private func makeScene() -> SCNScene {
        let scene = SCNScene()
        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.position = SCNVector3(0, 4.5, 10)
        camera.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(camera)

        let layout: [(TwinComponent.Kind, SCNVector3, CGFloat)] = [
            (.cpu, SCNVector3(0, 0.6, 0), 0.7),
            (.gpu, SCNVector3(1.6, 0.3, 0.4), 0.55),
            (.neuralEngine, SCNVector3(-1.6, 0.3, 0.4), 0.45),
            (.memory, SCNVector3(0, 0.2, 1.5), 0.9),
            (.ssd, SCNVector3(0, -0.2, -1.4), 0.8),
            (.battery, SCNVector3(-2.2, -0.6, -0.2), 0.7),
            (.fans, SCNVector3(2.2, -0.4, -0.2), 0.5),
            (.powerRails, SCNVector3(0, -1.0, 0), 1.1),
            (.wireless, SCNVector3(1.2, 1.2, -0.8), 0.35),
            (.thunderbolt, SCNVector3(-1.2, 1.2, -0.8), 0.35),
            (.usb, SCNVector3(2.4, 0.8, 1.0), 0.3),
            (.sensors, SCNVector3(-2.4, 0.8, 1.0), 0.3)
        ]
        for (kind, position, scale) in layout {
            let box = SCNBox(width: scale, height: scale * 0.35, length: scale, chamferRadius: 0.05)
            let node = SCNNode(geometry: box)
            node.name = kind.rawValue
            node.position = position
            scene.rootNode.addChildNode(node)
        }
        return scene
    }
}

// MARK: - Copilot

public struct CopilotView: View {
    let messages: [CopilotMessage]

    public var body: some View {
        List {
            Section {
                Text("Every statement is grounded in live samples. PulseMonitor will not invent WindowServer GPU load, FPS, or Neural Engine utilization.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ForEach(messages) { message in
                VStack(alignment: .leading, spacing: 8) {
                    Text(message.text)
                    if !message.actions.isEmpty {
                        ForEach(message.actions, id: \.self) { action in
                            Label(action, systemImage: "arrow.right.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("AI Copilot")
    }
}

// MARK: - Snapshots

public struct SnapshotsView: View {
    @Bindable var service: SnapshotService
    let onCapture: () -> Void
    @State private var left: SystemSnapshot.ID?
    @State private var right: SystemSnapshot.ID?

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Capture Snapshot", action: onCapture)
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                Spacer()
            }
            .padding()

            List(selection: $left) {
                ForEach(service.snapshots) { snapshot in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(snapshot.name).font(.headline)
                            Text(snapshot.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Compare as A") { left = snapshot.id }
                        Button("Compare as B") { right = snapshot.id }
                        Button(role: .destructive) { service.delete(snapshot.id) } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                    .tag(snapshot.id)
                }
            }

            if let a = service.snapshots.first(where: { $0.id == left }),
               let b = service.snapshots.first(where: { $0.id == right }) {
                Divider()
                List(service.diff(a, b)) { row in
                    HStack {
                        Text(row.label).frame(width: 120, alignment: .leading)
                        Text(row.before).foregroundStyle(.secondary)
                        Image(systemName: "arrow.right")
                        Text(row.after)
                        Spacer()
                        Text(row.direction.rawValue)
                            .foregroundStyle(row.direction == .improved ? .green : (row.direction == .worsened ? .orange : .secondary))
                    }
                }
                .frame(height: 220)
            }
        }
        .navigationTitle("Snapshots")
    }
}

// MARK: - Hardware DB

public struct HardwareDatabaseView: View {
    let inventory: HardwareInventory?
    let refresh: () -> Void

    public var body: some View {
        List {
            Section("Identity") {
                LabeledContent("Model", value: inventory?.modelIdentifier ?? "—")
                LabeledContent("CPU", value: inventory?.cpuBrand ?? "—")
                LabeledContent("Cores", value: inventory?.cpuCoreCount.map(String.init) ?? "—")
                LabeledContent("GPU", value: inventory?.gpuName ?? "—")
                LabeledContent("Memory", value: inventory?.memoryBytes.map(Formatters.bytes) ?? "—")
                LabeledContent("macOS", value: inventory?.osVersion ?? "—")
                LabeledContent("Wi‑Fi", value: inventory?.wifiInterface ?? "—")
                LabeledContent("Bluetooth", value: inventory?.bluetoothPresent == true ? "Present" : "Not found")
            }
            Section("Displays") { deviceRows(inventory?.displays ?? []) }
            Section("USB") { deviceRows(inventory?.usbDevices ?? []) }
            Section("PCI") { deviceRows(inventory?.pciDevices ?? []) }
            Section("Storage") { deviceRows(inventory?.storageDevices ?? []) }
            Section("Notes") {
                ForEach(inventory?.notes ?? [], id: \.self) { Text($0).foregroundStyle(.secondary) }
            }
        }
        .toolbar { Button("Refresh", action: refresh) }
        .navigationTitle("Hardware Database")
    }

    @ViewBuilder
    private func deviceRows(_ devices: [HardwareInventory.NamedDevice]) -> some View {
        if devices.isEmpty {
            Text("None discovered").foregroundStyle(.secondary)
        } else {
            ForEach(devices) { device in
                VStack(alignment: .leading) {
                    Text(device.name)
                    Text([device.vendor, device.detail].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - USB / Bluetooth / Display / Packages

public struct USBLabView: View {
    @Bindable var service: USBDeviceService
    @State private var ejectError: String?

    public var body: some View {
        List {
            ForEach(service.devices) { device in
                HStack {
                    VStack(alignment: .leading) {
                        Text(device.name)
                        Text([device.vendor, device.speed, device.locationID].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Battery / precise wattage for USB devices is not published by macOS for arbitrary peripherals.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    if device.canEject {
                        Button("Eject") {
                            ejectError = service.eject(device)
                        }
                    }
                }
            }
        }
        .overlay { if service.devices.isEmpty { ContentUnavailableView("No USB devices", systemImage: "usb") } }
        .alert("Eject", isPresented: Binding(get: { ejectError != nil }, set: { if !$0 { ejectError = nil } })) {
            Button("OK") { ejectError = nil }
        } message: { Text(ejectError ?? "") }
        .toolbar { Button("Refresh") { service.refresh() } }
        .navigationTitle("USB Devices")
        .onAppear { service.refresh() }
    }
}

public struct BluetoothLabView: View {
    @Bindable var service: BluetoothLabService

    public var body: some View {
        List {
            Section("Controller") {
                LabeledContent("State", value: service.stateDescription)
                HStack {
                    Button(service.isScanning ? "Stop Scan" : "Scan Nearby") {
                        service.isScanning ? service.stopScan() : service.startScan()
                    }
                }
            }
            Section("Nearby") {
                ForEach(service.peripherals) { peripheral in
                    HStack {
                        Text(peripheral.name)
                        Spacer()
                        Text(peripheral.rssi.map { "\($0) dBm" } ?? "RSSI —")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
            Section("Limits") {
                ForEach(service.notes, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("Bluetooth Lab")
        .onAppear { service.start() }
        .onDisappear { service.stopScan() }
    }
}

public struct DisplayLabView: View {
    @Bindable var service: DisplayLabService

    public var body: some View {
        List {
            if let change = service.lastRefreshChange {
                Section("Recent Change") { Text(change).foregroundStyle(.orange) }
            }
            Section("Displays") {
                ForEach(service.displays) { display in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(display.name + (display.isMain ? " (Main)" : "")).font(.headline)
                        Text(String(format: "%.0f×%.0f points · %.0f×%.0f pixels · %dx · %d Hz",
                                       display.widthPoints, display.heightPoints,
                                       display.widthPixels, display.heightPixels,
                                       Int(display.scale), display.refreshHz))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let space = display.colorSpaceName {
                            Text(space).font(.caption2).foregroundStyle(.tertiary)
                        }
                        Text("Night Shift / True Tone state is not readable via public APIs.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .toolbar { Button("Refresh") { service.refresh() } }
        .navigationTitle("Display Lab")
        .onAppear { service.refresh() }
    }
}

public struct PackageManagerView: View {
    @Bindable var service: PackageManagerService

    public var body: some View {
        List {
            if service.isScanning {
                ProgressView("Scanning toolchains…")
            }
            ForEach(service.tools) { tool in
                VStack(alignment: .leading) {
                    Text(tool.name).font(.headline)
                    Text(tool.version ?? "Installed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let path = tool.path {
                        Text(path).font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .overlay {
            if service.tools.isEmpty && !service.isScanning {
                ContentUnavailableView("No toolchains found", systemImage: "shippingbox")
            }
        }
        .toolbar {
            Button("Scan") { Task { await service.scan() } }
        }
        .navigationTitle("Package Manager")
        .task { await service.scan() }
    }
}

// MARK: - Game Lab

public struct GameLabView: View {
    @Bindable var service: GameLabService
    @State private var selectedID: String?

    public var body: some View {
        HSplitView {
            List(selection: $selectedID) {
                Section("Session") {
                    Toggle("Record samples", isOn: Binding(
                        get: { service.isRecording },
                        set: { $0 ? service.startRecording() : service.stopRecording() }
                    ))
                    ForEach(service.activeGames, id: \.pid) { game in
                        Label(game.name, systemImage: "gamecontroller")
                    }
                }
                Section("Library") {
                    ForEach(service.library) { entry in
                        VStack(alignment: .leading) {
                            Text(entry.name)
                            Text("\(entry.platform.displayName) · \(entry.samples.count) samples")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(entry.id)
                    }
                }
                Section("Shader surge heuristics") {
                    ForEach(service.shaderSpikes.prefix(12)) { spike in
                        VStack(alignment: .leading) {
                            Text(spike.processName)
                            Text(spike.detail).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Section("Java / Minecraft") {
                    ForEach(service.javaInsights) { insight in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(insight.processName) · PID \(insight.pid)")
                            Text(String(format: "%.1f%% CPU · %@ · %d threads",
                                           insight.cpuPercent, Formatters.bytes(insight.memoryBytes), insight.threadCount))
                                .font(.caption)
                            ForEach(insight.notes, id: \.self) {
                                Text($0).font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
            .frame(minWidth: 280)

            ScrollView {
                Text(service.performanceReport(for: selectedID ?? service.library.first?.id ?? ""))
                    .font(.body.monospaced())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
        .navigationTitle("Game Performance Lab")
    }
}

// MARK: - Workspaces / Menu Bar Studio / Web Dashboard / Search

public struct WorkspacesView: View {
    @Bindable var store: WorkspaceStore
    let settings: AppSettings
    let profiles: PowerProfileService
    var onApply: (SidebarItem?) -> Void

    public var body: some View {
        List {
            ForEach(store.workspaces) { workspace in
                HStack {
                    Label(workspace.name, systemImage: workspace.symbol)
                    Spacer()
                    if store.activeID == workspace.id {
                        Text("Active").foregroundStyle(.secondary).font(.caption)
                    }
                    Button("Apply") {
                        onApply(store.apply(workspace, settings: settings, profiles: profiles))
                    }
                    Button(role: .destructive) { store.delete(workspace.id) } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .navigationTitle("Workspaces")
    }
}

public struct MenuBarStudioView: View {
    @Bindable var store: MenuBarStudioStore

    public var body: some View {
        Form {
            Section("Items") {
                ForEach($store.configuration.items) { $item in
                    Toggle(item.kind.displayName, isOn: $item.enabled)
                }
            }
            Section("Layout") {
                Toggle("Compact separators", isOn: $store.configuration.compact)
                Toggle("Mini graph (reserved)", isOn: $store.configuration.showMiniGraph)
                Text("Mini graphs stay off by default to protect menu-bar CPU cost.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Menu Bar Studio")
    }
}

public struct WebDashboardView: View {
    @Bindable var server: WebDashboardServer

    public var body: some View {
        Form {
            Section("Local Network Dashboard") {
                LabeledContent("Status", value: server.isRunning ? "Running" : "Stopped")
                LabeledContent("URL") {
                    Text(server.bindAddressDescription)
                        .textSelection(.enabled)
                        .font(.caption.monospaced())
                }
                if let error = server.lastError {
                    Text(error).foregroundStyle(.red)
                }
                HStack {
                    Button(server.isRunning ? "Stop" : "Start") {
                        server.isRunning ? server.stop() : server.start()
                    }
                    Button("Rotate Token") { server.rotateToken() }
                }
                Text("Only devices with the token can read metrics. Bound to localhost by default via 127.0.0.1.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Web Dashboard")
    }
}

public struct UniversalSearchView: View {
    @Binding var query: String
    let hits: [SearchHit]
    var onOpen: (SidebarItem) -> Void

    public var body: some View {
        VStack(spacing: 0) {
            TextField("Search modules, processes, hardware, logs…", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding()
            List(hits) { hit in
                Button {
                    if let item = hit.sidebarItem { onOpen(item) }
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(hit.title)
                            Text(hit.subtitle).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(hit.kind.rawValue).font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle("Search")
    }
}

public struct WindowServerLabView: View {
    let processes: [ProcessInfoModel]

    public var body: some View {
        let ws = processes.first(where: { $0.name == "WindowServer" })
        List {
            Section("Measured") {
                LabeledContent("WindowServer CPU", value: ws.map { Formatters.percent($0.cpuPercent) } ?? "Not visible")
                LabeledContent("WindowServer RAM", value: ws.map { Formatters.bytes($0.memoryBytes) } ?? "—")
                LabeledContent("Threads", value: ws.map { "\($0.threadCount)" } ?? "—")
            }
            Section("Honest limits") {
                Text("GPU time spent inside WindowServer is not readable without root / private APIs. PulseMonitor only reports the process CPU and memory it can inspect.")
                    .foregroundStyle(.secondary)
                Text("Transparency, Mission Control and wallpaper cost are inferred only when WindowServer CPU is elevated — never shown as fabricated GPU percentages.")
                    .foregroundStyle(.secondary)
            }
            Section("Suggestions when CPU is high") {
                Text("• Reduce transparency & motion in System Settings → Accessibility")
                Text("• Disconnect unused external displays")
                Text("• Prefer still wallpapers over dynamic ones while on battery")
            }
        }
        .navigationTitle("WindowServer")
    }
}

public struct DeveloperLabView: View {
    let processes: [ProcessInfoModel]
    let metrics: SystemMetrics?

    public var body: some View {
        let xcode = processes.filter { $0.name.localizedCaseInsensitiveContains("Xcode") || $0.name == "swift-frontend" || $0.name == "clang" }
        List {
            Section("Build-related processes") {
                if xcode.isEmpty {
                    Text("No Xcode/swift-frontend processes right now.").foregroundStyle(.secondary)
                } else {
                    ForEach(xcode, id: \.pid) { process in
                        LabeledContent(process.name, value: String(format: "%.1f%% · %@", process.cpuPercent, Formatters.bytes(process.memoryBytes)))
                    }
                }
            }
            Section("Runtime") {
                LabeledContent("Process count", value: "\(processes.count)")
                LabeledContent("CPU package", value: Formatters.percent(metrics?.cpu.totalUsage ?? 0))
                LabeledContent("Memory pressure", value: metrics?.memory.pressure.displayName ?? "—")
            }
            Section("Limits") {
                Text("Simulator FPS, Instruments-style time profiles and Metal frame captures require Xcode tools. PulseMonitor surfaces live process cost only.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Developer Lab")
    }
}

public struct LogAnalyzerView: View {
    let events: [SystemEvent]

    public var body: some View {
        let crashes = events.filter { $0.category == .crash || $0.category == .kernelPanic }
        let thermal = events.filter { $0.category == .thermal }
        let sleep = events.filter { $0.category == .sleepWake }
        List {
            Section("Recurring patterns") {
                LabeledContent("Crash / panic events", value: "\(crashes.count)")
                LabeledContent("Thermal events", value: "\(thermal.count)")
                LabeledContent("Sleep / wake events", value: "\(sleep.count)")
            }
            Section("Latest issues") {
                ForEach(events.filter { $0.severity == .critical || $0.severity == .warning }.prefix(30)) { event in
                    VStack(alignment: .leading) {
                        Text(event.title).font(.headline)
                        if let detail = event.detail {
                            Text(detail).font(.caption).foregroundStyle(.secondary)
                        }
                        Text(event.date.formatted()).font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .navigationTitle("Log Analyzer")
    }
}

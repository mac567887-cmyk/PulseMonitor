import SwiftUI
import Charts

/// Timeline — scrub back through recorded history.
///
/// Data comes from the SQLite history database, so the reachable range depends
/// on the retention setting and on how long the app has been running. The view
/// reports the true extent rather than drawing an empty 24-hour axis.
public struct TimelineView: View {
    let history: HistoryRepository
    let eventLog: EventLogService
    @Bindable var settings: AppSettings

    @State private var points: [HistoryRepository.HistoryPoint] = []
    @State private var isLoading = true
    @State private var scrubPosition: Date?
    @State private var visibleWindow: HistoryRetention = .oneHour

    public init(history: HistoryRepository, eventLog: EventLogService, settings: AppSettings) {
        self.history = history
        self.eventLog = eventLog
        self.settings = settings
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.gridSpacing) {
                header

                if isLoading {
                    loadingCard
                } else if points.count < 2 {
                    emptyCard
                } else {
                    scrubberCard
                    chart(title: "CPU & GPU", systemImage: "cpu") { cpuGpuChart }
                    chart(title: "Memory", systemImage: "memorychip") { memoryChart }
                    if points.contains(where: { $0.temperature != nil }) {
                        chart(title: "Temperature", systemImage: "thermometer.medium") { temperatureChart }
                    }
                    chart(title: "Network", systemImage: "network") { networkChart }
                }
            }
            .padding(DesignTokens.sectionSpacing)
        }
        .background(AmbientBackdrop())
        .navigationTitle("Timeline")
        .task { await load() }
    }

    // MARK: - Header

    private var header: some View {
        GlassSection(title: "Timeline", systemImage: "clock.arrow.circlepath") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Replay what your Mac was doing. Drag across any chart to read the exact values at that moment.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Picker("Window", selection: $visibleWindow) {
                    ForEach(HistoryRetention.allCases) { retention in
                        Text(retention.displayName).tag(retention)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: visibleWindow) { _, _ in
                    Task { await load() }
                }

                HStack {
                    if let first = points.first, let last = points.last {
                        Text("\(points.count) samples from \(first.timestamp.formatted(date: .omitted, time: .shortened)) to \(last.timestamp.formatted(date: .omitted, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    } else {
                        Text("No samples in this window")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Button {
                        Task { await load() }
                    } label: {
                        Label("Reload", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private var loadingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            ShimmerPlaceholder(height: 20)
            ShimmerPlaceholder(height: 120)
        }
        .glassCard()
    }

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Not enough history yet", systemImage: "hourglass")
                .font(.headline)
            Text("PulseMonitor records one sample per polling interval into a local database. Leave it running and this timeline will fill in. Retention is currently set to \(settings.historyRetention.displayName.lowercased()).")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    // MARK: - Scrubber

    private var scrubberCard: some View {
        let sample = scrubPosition.flatMap { nearest(to: $0) } ?? points.last

        return GlassSection(title: "Playhead", systemImage: "play.circle") {
            VStack(alignment: .leading, spacing: 10) {
                if let sample {
                    Text(sample.timestamp.formatted(date: .abbreviated, time: .standard))
                        .font(.headline)
                        .monospacedDigit()
                        .contentTransition(.numericText())

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 110, maximum: 200), spacing: 8)],
                        spacing: 8
                    ) {
                        readout("CPU", String(format: "%.0f%%", sample.cpu), .blue)
                        if let gpu = sample.gpu {
                            readout("GPU", String(format: "%.0f%%", gpu), .purple)
                        }
                        readout("Memory", String(format: "%.0f%%", sample.memory), .green)
                        if let temperature = sample.temperature {
                            readout("Temp", String(format: "%.0f°C", temperature), .orange)
                        }
                        readout("Down", "\(Formatters.bytes(UInt64(max(0, sample.networkIn))))/s", .teal)
                        readout("Up", "\(Formatters.bytes(UInt64(max(0, sample.networkOut))))/s", .indigo)
                    }
                }

                // Events inside the window give the numbers context.
                let windowEvents = eventsInWindow()
                if !windowEvents.isEmpty {
                    Divider()
                    Text("\(windowEvents.count) events in this window")
                        .font(.caption.weight(.medium))
                    ForEach(windowEvents.prefix(5)) { event in
                        HStack(spacing: 6) {
                            Image(systemName: event.category.symbol)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(event.title).font(.caption)
                            Spacer()
                            Text(event.date.formatted(date: .omitted, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
    }

    private func readout(_ label: String, _ value: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(tint.opacity(0.10))
        )
    }

    // MARK: - Charts

    private func chart<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        GlassSection(title: title, systemImage: systemImage) {
            content()
                .frame(height: 170)
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(.clear)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        guard let plotFrame = proxy.plotFrame else { return }
                                        let origin = geometry[plotFrame].origin
                                        let x = value.location.x - origin.x
                                        if let date: Date = proxy.value(atX: x) {
                                            scrubPosition = date
                                        }
                                    }
                            )
                    }
                }
        }
    }

    private var cpuGpuChart: some View {
        Chart {
            ForEach(points) { point in
                AreaMark(
                    x: .value("Time", point.timestamp),
                    y: .value("CPU", point.cpu)
                )
                .foregroundStyle(
                    LinearGradient(colors: [.blue.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom)
                )
                .interpolationMethod(.monotone)

                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("CPU", point.cpu)
                )
                .foregroundStyle(.blue)
                .interpolationMethod(.monotone)

                if let gpu = point.gpu {
                    LineMark(
                        x: .value("Time", point.timestamp),
                        y: .value("GPU", gpu)
                    )
                    .foregroundStyle(.purple)
                    .interpolationMethod(.monotone)
                }
            }
            playhead
        }
        .chartYScale(domain: 0...100)
    }

    private var memoryChart: some View {
        Chart {
            ForEach(points) { point in
                AreaMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Memory", point.memory)
                )
                .foregroundStyle(
                    LinearGradient(colors: [.green.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom)
                )
                .interpolationMethod(.monotone)

                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Memory", point.memory)
                )
                .foregroundStyle(.green)
                .interpolationMethod(.monotone)
            }
            playhead
        }
        .chartYScale(domain: 0...100)
    }

    private var temperatureChart: some View {
        Chart {
            ForEach(points.filter { $0.temperature != nil }) { point in
                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Temperature", point.temperature ?? 0)
                )
                .foregroundStyle(.orange)
                .interpolationMethod(.monotone)
            }
            playhead
        }
    }

    private var networkChart: some View {
        Chart {
            ForEach(points) { point in
                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Down", point.networkIn),
                    series: .value("Direction", "Down")
                )
                .foregroundStyle(.teal)
                .interpolationMethod(.monotone)

                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Up", point.networkOut),
                    series: .value("Direction", "Up")
                )
                .foregroundStyle(.indigo)
                .interpolationMethod(.monotone)
            }
            playhead
        }
    }

    @ChartContentBuilder
    private var playhead: some ChartContent {
        if let scrubPosition {
            RuleMark(x: .value("Playhead", scrubPosition))
                .foregroundStyle(Color.primary.opacity(0.35))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }
    }

    // MARK: - Data

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        let end = Date()
        let start = end.addingTimeInterval(-visibleWindow.seconds)
        points = await history.query(from: start, to: end)
        scrubPosition = nil
    }

    private func nearest(to date: Date) -> HistoryRepository.HistoryPoint? {
        points.min {
            abs($0.timestamp.timeIntervalSince(date)) < abs($1.timestamp.timeIntervalSince(date))
        }
    }

    private func eventsInWindow() -> [SystemEvent] {
        guard let first = points.first?.timestamp, let last = points.last?.timestamp else { return [] }
        return eventLog.events
            .filter { $0.date >= first && $0.date <= last }
            .sorted { $0.date > $1.date }
    }
}

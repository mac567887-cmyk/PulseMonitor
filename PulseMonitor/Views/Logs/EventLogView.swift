import SwiftUI

/// Advanced logging.
///
/// Sleep, wake, mount, thermal and application events are captured live from the
/// system notification centres. Crash reports and kernel panics are read from
/// the diagnostic report directories macOS already maintains.
public struct EventLogView: View {
    let eventLog: EventLogService
    @State private var category: SystemEvent.Category?
    @State private var searchText = ""

    public init(eventLog: EventLogService) {
        self.eventLog = eventLog
    }

    private var filtered: [SystemEvent] {
        var events = eventLog.events(in: category)
        let query = searchText.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            events = events.filter {
                $0.title.localizedCaseInsensitiveContains(query)
                    || ($0.detail?.localizedCaseInsensitiveContains(query) ?? false)
            }
        }
        return events
    }

    public var body: some View {
        VStack(spacing: 0) {
            toolbar

            if filtered.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text(category == nil ? "No events recorded yet" : "No \(category!.displayName.lowercased()) events")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filtered) { event in
                    row(event)
                }
                .listStyle(.inset)
            }
        }
        .background(AmbientBackdrop())
        .navigationTitle("Logs")
    }

    private var toolbar: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search events", text: $searchText)
                    .textFieldStyle(.plain)
                Spacer()
                Text("\(filtered.count) events")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Button {
                    eventLog.clear()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .help("Clear the event log")
            }
            .padding(7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06))
            )

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    chip(nil, label: "All")
                    ForEach(SystemEvent.Category.allCases) { candidate in
                        let count = eventLog.events.count { $0.category == candidate }
                        if count > 0 {
                            chip(candidate, label: "\(candidate.displayName) \(count)")
                        }
                    }
                }
            }
        }
        .padding(10)
    }

    private func chip(_ candidate: SystemEvent.Category?, label: String) -> some View {
        let isActive = category == candidate

        return Button {
            withAnimation(DesignTokens.Motion.quick) {
                category = isActive && candidate != nil ? nil : candidate
            }
        } label: {
            Text(label)
                .font(.caption)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(isActive ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.06))
                )
                .foregroundStyle(isActive ? Color.accentColor : .secondary)
        }
        .buttonStyle(.plain)
    }

    private func row(_ event: SystemEvent) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: event.category.symbol)
                .foregroundStyle(tint(for: event.severity))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.callout)
                if let detail = event.detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 8)

            Text(event.date.formatted(date: .abbreviated, time: .standard))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .padding(.vertical, 3)
    }

    private func tint(for severity: SystemEvent.Severity) -> Color {
        switch severity {
        case .info: .secondary
        case .notice: .blue
        case .warning: .orange
        case .critical: .red
        }
    }
}

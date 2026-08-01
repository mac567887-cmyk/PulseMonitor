import SwiftUI

public struct AnalysisDetailView: View {
    @Bindable var viewModel: AnalysisViewModel

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader("AI Analysis Engine", subtitle: "Rule-based bottleneck detection — fully on-device")
                Text(viewModel.report?.narrative ?? "Waiting for samples…")
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                ForEach(viewModel.report?.findings ?? []) { finding in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(finding.title).font(.headline)
                            Spacer()
                            Text(finding.severity.rawValue.uppercased())
                                .font(.caption2.weight(.bold))
                                .padding(5)
                                .background(severityColor(finding.severity).opacity(0.15), in: Capsule())
                                .foregroundStyle(severityColor(finding.severity))
                        }
                        Text(finding.summary)
                        Text(finding.detail).font(.callout).foregroundStyle(.secondary)
                        if !finding.relatedProcesses.isEmpty {
                            Text("Related: \(finding.relatedProcesses.joined(separator: ", "))")
                                .font(.caption)
                        }
                        ForEach(finding.recommendations, id: \.self) { rec in
                            Label(rec, systemImage: "checkmark.circle")
                                .font(.callout)
                        }
                    }
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .padding(24)
        }
        .background(AmbientBackground())
    }

    private func severityColor(_ severity: BottleneckFinding.Severity) -> Color {
        switch severity {
        case .info: .blue
        case .warning: .orange
        case .critical: .red
        }
    }
}

import SwiftUI

/// Version 5 AI Copilot dashboard — Athena / PIE.
public struct AICopilotDashboard: View {
    @Bindable var athena: AthenaSession
    let health: HealthScoreReport?
    let healthHistory: [HealthScoreReport]
    let legacyMessages: [CopilotMessage]
    let developerMode: Bool

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                statusRow
                askBar
                if let answer = athena.snapshot?.nlAnswer {
                    answerCard(answer)
                }
                bottleneckRow
                insightsSection
                predictionsSection
                anomaliesSection
                suggestionsSection
                timelineSection
                briefingSection
                knowledgeSection
                if developerMode || !(athena.snapshot?.developerTrace.isEmpty ?? true) {
                    developerSection
                }
                legacySection
            }
            .padding(20)
        }
        .navigationTitle("AI Copilot")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Athena")
                .font(.largeTitle.weight(.bold))
            Text("Performance Intelligence Engine — offline, evidence-backed, never invents sensors.")
                .foregroundStyle(.secondary)
        }
    }

    private var statusRow: some View {
        let snap = athena.snapshot
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
            statusTile("System Mood", "\(snap?.mood.symbol ?? "🟢") \(snap?.mood.label ?? "—")")
            statusTile("Health", String(format: "%.0f", snap?.overallHealth ?? health?.overall ?? 100))
            statusTile("Optimization", String(format: "%.0f", snap?.optimizationScore ?? 100))
            statusTile("Workload", snap?.workload.kind.displayName ?? "—")
        }
    }

    private func statusTile(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var askBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Natural Language Search").font(.headline)
            HStack {
                TextField("Why is my Mac hot?", text: $athena.question)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { athena.ask() }
                Button("Ask", action: athena.ask)
                    .keyboardShortcut(.return, modifiers: [])
                Button("Voice Ready") {
                    athena.handleVoice(athena.question.isEmpty ? "How is my system?" : athena.question)
                }
                .help("Routes to the modular voice intent layer (speech recognition can be plugged in later).")
            }
            if let voice = athena.lastVoice {
                Text("Voice intent: \(voice.intent.rawValue) (\(Int(voice.confidence))%) — \(voice.spokenReply)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .glassCard()
    }

    private func answerCard(_ answer: ConfidenceFinding) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(answer.title).font(.headline)
                Spacer()
                confidenceBadge(answer.confidence, estimate: answer.isEstimate)
            }
            Text(answer.summary)
            Text(answer.why).foregroundStyle(.secondary)
            if !answer.evidence.isEmpty {
                Text("Evidence: " + answer.evidence.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .glassCard()
    }

    private var bottleneckRow: some View {
        HStack(alignment: .top, spacing: 12) {
            bottleneckCard(
                title: "Current Bottleneck",
                finding: athena.snapshot?.currentBottleneck
            )
            predictionBottleneckCard(athena.snapshot?.predictedBottleneck)
        }
    }

    private func bottleneckCard(title: String, finding: ConfidenceFinding?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            if let finding {
                HStack {
                    Text(finding.title).font(.subheadline.weight(.semibold))
                    Spacer()
                    confidenceBadge(finding.confidence, estimate: finding.isEstimate)
                }
                Text(finding.summary)
                Text(finding.why).font(.callout).foregroundStyle(.secondary)
            } else {
                Text("No dominant bottleneck in the latest sample.")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func predictionBottleneckCard(_ prediction: PIEPrediction?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Predicted Future Bottleneck").font(.headline)
            if let prediction {
                HStack {
                    Text(prediction.horizon.label).font(.subheadline.weight(.semibold))
                    Spacer()
                    confidenceBadge(prediction.confidence, estimate: prediction.isEstimate)
                }
                Text(prediction.summary)
                if !prediction.evidence.isEmpty {
                    Text(prediction.evidence.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Not enough samples yet for a trend-based prediction.")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var insightsSection: some View {
        section("Live AI Insights", items: athena.snapshot?.insights ?? []) { item in
            findingRow(item)
        }
    }

    private var predictionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Predictions").font(.headline)
            if let preds = athena.snapshot?.predictions, !preds.isEmpty {
                ForEach(preds.prefix(8)) { p in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("\(p.kind.rawValue) · \(p.horizon.label)")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            confidenceBadge(p.confidence, estimate: p.isEstimate)
                        }
                        Text(p.summary).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            } else {
                Text("Collecting samples for 5 / 15 / 30 / 60 minute horizons…")
                    .foregroundStyle(.secondary)
            }
        }
        .glassCard()
    }

    private var anomaliesSection: some View {
        section("Anomalies", items: athena.snapshot?.anomalies ?? []) { findingRow($0) }
    }

    private var suggestionsSection: some View {
        section("AI Suggestions (never auto-applied)", items: athena.snapshot?.suggestions ?? []) { findingRow($0) }
    }

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("AI Timeline").font(.headline)
            let events = Array((athena.timelineLog.isEmpty ? athena.snapshot?.timeline ?? [] : athena.timelineLog).suffix(12).reversed())
            if events.isEmpty {
                Text("Major metric changes will appear here with explanations.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(events) { event in
                    HStack(alignment: .top) {
                        Text(event.timestamp, style: .time)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 64, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.title).font(.subheadline.weight(.semibold))
                            Text(event.reason).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        confidenceBadge(event.confidence, estimate: false)
                    }
                }
            }
        }
        .glassCard()
    }

    private var briefingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Daily System Briefing").font(.headline)
            if let b = athena.snapshot?.briefing {
                Text(b.narrative)
                ForEach(b.highlights, id: \.self) { Text("• \($0)").foregroundStyle(.secondary) }
                if !b.recommendations.isEmpty {
                    Text("Recommendations").font(.subheadline.weight(.semibold)).padding(.top, 4)
                    ForEach(b.recommendations, id: \.self) { Text("• \($0)") }
                }
            } else {
                Text("Briefing appears after the first PIE evaluation.")
                    .foregroundStyle(.secondary)
            }
        }
        .glassCard()
    }

    private var knowledgeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Knowledge Engine").font(.headline)
            Picker("Topic", selection: $athena.selectedKnowledgeTopic) {
                Text("CPU").tag("cpu")
                Text("GPU").tag("gpu")
                Text("Memory").tag("memory")
                Text("Battery").tag("battery")
                Text("Storage").tag("storage")
            }
            .pickerStyle(.segmented)
            .onChange(of: athena.selectedKnowledgeTopic) { _, _ in
                // Article refreshes on next tick; keep last metrics via session habit.
            }
            if let article = athena.knowledgeArticle {
                Text(article.definition)
                labeled("Healthy range", article.healthyRange)
                labeled("Current", article.currentStatus)
                labeled("Why it matters", article.importance)
                Text("Common problems").font(.subheadline.weight(.semibold))
                ForEach(article.commonProblems, id: \.self) { Text("• \($0)").font(.caption) }
                Text("Tips").font(.subheadline.weight(.semibold))
                ForEach(article.tips, id: \.self) { Text("• \($0)").font(.caption) }
            }
        }
        .glassCard()
    }

    private var developerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Developer Mode — Reasoning").font(.headline)
            ForEach(athena.snapshot?.developerTrace ?? [], id: \.self) {
                Text($0).font(.system(.caption, design: .monospaced))
            }
            if let habits = Optional(athena.habits), habits.sampleCount > 0 {
                Text("Learned samples: \(habits.sampleCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let cpu = habits.typicalCPUPercent {
                    Text(String(format: "Typical CPU %.0f%%", cpu)).font(.caption)
                }
            }
        }
        .glassCard()
    }

    private var legacySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Health Timeline").font(.headline)
            if healthHistory.count >= 2 {
                Text(String(format: "Buffered health points: %d · latest %.0f", healthHistory.count, healthHistory.last?.overall ?? 0))
                    .foregroundStyle(.secondary)
            } else {
                Text("Health history will fill as samples arrive.")
                    .foregroundStyle(.secondary)
            }
            if !legacyMessages.isEmpty {
                Text("Companion notes").font(.subheadline.weight(.semibold))
                ForEach(legacyMessages.prefix(4)) { msg in
                    Text("• \(msg.text)").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .glassCard()
    }

    private func section<T: Identifiable>(_ title: String, items: [T], @ViewBuilder row: @escaping (T) -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            if items.isEmpty {
                Text("None right now.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(items.prefix(8)) { row($0) }
            }
        }
        .glassCard()
    }

    private func findingRow(_ item: ConfidenceFinding) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(item.title).font(.subheadline.weight(.semibold))
                Spacer()
                confidenceBadge(item.confidence, estimate: item.isEstimate)
            }
            Text(item.summary)
            Text(item.why).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func confidenceBadge(_ value: Double, estimate: Bool) -> some View {
        Text(String(format: estimate ? "est. %.0f%%" : "%.0f%%", value))
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.blue.opacity(0.15), in: Capsule())
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value)
        }
    }
}

import SwiftUI

public struct GamesView: View {
    @Bindable var viewModel: GamesViewModel

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    SectionHeader("Game Detector", subtitle: "Steam, Minecraft, emulators, Wine/Whisky, and more")
                    Spacer()
                    Button("Analyze") { viewModel.refreshAnalysis() }
                        .buttonStyle(.borderedProminent)
                }

                if viewModel.games.isEmpty {
                    ContentUnavailableView("No Games Detected", systemImage: "gamecontroller", description: Text("Launch a supported game or emulator to begin analysis."))
                } else {
                    ForEach(viewModel.games) { game in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "gamecontroller.fill")
                                Text(game.name).font(.headline)
                                Spacer()
                                Text(Formatters.percent(game.cpuPercent, digits: 1))
                            }
                            Text(game.executablePath ?? "")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }

                ForEach(viewModel.findings) { finding in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(finding.title).font(.headline)
                        Text(finding.detail)
                        ForEach(finding.recommendations, id: \.self) { rec in
                            Label(rec, systemImage: "lightbulb")
                                .font(.callout)
                        }
                    }
                    .padding()
                    .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .padding(24)
        }
        .background(AmbientBackground())
        .onAppear { viewModel.refreshAnalysis() }
    }
}

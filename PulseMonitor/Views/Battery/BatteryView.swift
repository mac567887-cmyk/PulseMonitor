import SwiftUI

public struct BatteryView: View {
    @Bindable var viewModel: BatteryViewModel

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SectionHeader("Battery & Power")
                if viewModel.metrics?.isPresent == true, let b = viewModel.metrics {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: 12) {
                        tile("Charge", Formatters.percent(b.chargePercent ?? 0))
                        tile("Health", Formatters.percent(b.healthPercent ?? 0))
                        tile("Cycles", b.cycleCount.map(String.init) ?? "—")
                        tile("Voltage", b.voltagemV.map { String(format: "%.0f mV", $0) } ?? "—")
                        tile("Current", b.amperagemA.map { String(format: "%.0f mA", $0) } ?? "—")
                        tile("Power", Formatters.watts(b.wattage))
                        tile("Source", b.powerSource.rawValue)
                        tile("Remaining", b.timeRemainingMinutes.map { "\($0) min" } ?? "—")
                    }
                } else {
                    ContentUnavailableView("No Battery", systemImage: "powerplug", description: Text("This Mac is running on AC power without an internal battery."))
                }
            }
            .padding(24)
        }
        .background(AmbientBackground())
    }

    private func tile(_ t: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(t).font(.caption).foregroundStyle(.secondary)
            Text(v).font(.title3.weight(.semibold))
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

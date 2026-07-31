import SwiftUI

public struct ThermalView: View {
    @Bindable var viewModel: ThermalViewModel

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SectionHeader("Thermal Analysis", subtitle: viewModel.metrics?.throttleReason)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160))], spacing: 12) {
                    tile("State", viewModel.metrics?.thermalState.displayName ?? "—")
                    tile("CPU Temp", Formatters.celsius(viewModel.metrics?.cpuTemperatureC))
                    tile("GPU Temp", Formatters.celsius(viewModel.metrics?.gpuTemperatureC))
                    tile("Battery Temp", Formatters.celsius(viewModel.metrics?.batteryTemperatureC))
                    tile("SSD Temp", Formatters.celsius(viewModel.metrics?.ssdTemperatureC))
                    tile("Throttling", viewModel.metrics?.isThrottling == true ? "Yes" : "No")
                }
                if let fans = viewModel.metrics?.fanSpeedsRPM, !fans.isEmpty {
                    ForEach(fans) { fan in
                        HStack {
                            Text(fan.name)
                            Spacer()
                            Text(Formatters.rpm(fan.rpm))
                        }
                    }
                } else {
                    Text("Fan RPM requires SMC access not exposed by public APIs on this Mac. Thermal state from ProcessInfo is authoritative for throttling detection.")
                        .foregroundStyle(.secondary)
                        .font(.callout)
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

import Foundation
import Darwin
import IOKit
import IOKit.ps

/// Resolves what this specific Mac and OS build will actually let the app do.
///
/// Everything mutating in PulseMonitor is gated on this service. When a control
/// cannot be honoured the reason is surfaced verbatim in the UI rather than the
/// control being hidden or, worse, shown as if it worked.
public actor CapabilityService {
    private var cached: HostCapabilities?

    public init() {}

    public func capabilities() -> HostCapabilities {
        if let cached { return cached }
        let resolved = Self.resolve()
        cached = resolved
        return resolved
    }

    private static func resolve() -> HostCapabilities {
        let appleSilicon = isAppleSilicon()
        let model = sysctlString("hw.model")
        let chip = sysctlString("machdep.cpu.brand_string")
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let battery = hasBattery()
        let smc = smcAccessState()

        // Apple Silicon exposes no public or private write path to fan control;
        // the SMC on those machines rejects writes from user space entirely.
        let fanControl: CapabilityState = appleSilicon
            ? .unsupported(reason: "Apple Silicon restricts manual fan control.")
            : fanControlStateForIntel(smc: smc)

        let fanReadout: CapabilityState = appleSilicon
            ? .unsupported(reason: "Apple Silicon does not publish fan RPM through a public API.")
            : smc

        return HostCapabilities(
            isAppleSilicon: appleSilicon,
            modelIdentifier: model.isEmpty ? "Unknown" : model,
            chipName: chip.isEmpty ? (appleSilicon ? "Apple Silicon" : "Intel") : chip,
            osVersion: os,
            hasBattery: battery,
            fanControl: fanControl,
            fanReadout: fanReadout,
            smcAccess: smc,
            frameRateOverlay: .unsupported(
                reason: "Measuring another app's frame rate requires private APIs or Metal's HUD; PulseMonitor will not fake it."
            )
        )
    }

    private static func isAppleSilicon() -> Bool {
        // Report the real hardware even when running translated under Rosetta.
        var translated: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("sysctl.proc_translated", &translated, &size, nil, 0) == 0, translated == 1 {
            return true
        }
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }

    /// AppleSMC can be opened read-only on Intel Macs. Writing fan targets needs
    /// a privileged helper, which PulseMonitor does not install.
    private static func smcAccessState() -> CapabilityState {
        guard let matching = IOServiceMatching("AppleSMC") else {
            return .unsupported(reason: "AppleSMC is not present on this machine.")
        }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else {
            return .unsupported(reason: "AppleSMC is not present on this machine.")
        }
        IOObjectRelease(service)
        return .supported
    }

    private static func fanControlStateForIntel(smc: CapabilityState) -> CapabilityState {
        guard smc.isSupported else { return smc }
        return .requiresPrivileges(
            reason: "Writing fan targets on Intel Macs requires a privileged SMC helper, which PulseMonitor does not install."
        )
    }

    private static func hasBattery() -> Bool {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else {
            return false
        }
        for source in list {
            guard let desc = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any] else {
                continue
            }
            if desc[kIOPSTypeKey] as? String == kIOPSInternalBatteryType { return true }
        }
        return false
    }

    private static func sysctlString(_ key: String) -> String {
        var size = 0
        guard sysctlbyname(key, nil, &size, nil, 0) == 0, size > 0 else { return "" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(key, &buffer, &size, nil, 0) == 0 else { return "" }
        return String(cString: buffer)
    }
}

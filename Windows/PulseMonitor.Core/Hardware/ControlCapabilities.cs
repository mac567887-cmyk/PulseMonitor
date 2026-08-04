using PulseMonitor.Core.Models;

namespace PulseMonitor.Core.Hardware;

/// <summary>
/// Fan / RGB / overclock write paths are capability-gated.
/// Without signed vendor bridges, controls remain disabled — never fake.
/// </summary>
public static class ControlCapabilities
{
    public static IReadOnlyList<CapabilityState> Snapshot()
    {
        var rgbBridges = DetectRgbBridges();
        var fanBridge = File.Exists(Path.Combine(AppContext.BaseDirectory, "bridges", "FanBridge.dll"));

        return new[]
        {
            new CapabilityState
            {
                Id = "fanWrite",
                Status = fanBridge ? "available" : "unsupported",
                Reason = fanBridge
                    ? "Optional FanBridge.dll detected — confirm before applying curves."
                    : "No EC/BMC fan bridge loaded. Manual/gaming/silent/custom curves stay disabled."
            },
            new CapabilityState
            {
                Id = "rgbControl",
                Status = rgbBridges.Count > 0 ? "partial" : "unsupported",
                Reason = rgbBridges.Count > 0
                    ? "Detected host apps: " + string.Join(", ", rgbBridges) + ". PulseMonitor catalogues only unless an SDK bridge is installed."
                    : "ASUS Aura / MSI Mystic Light / Corsair iCUE / Razer / etc. not detected as running hosts."
            },
            new CapabilityState
            {
                Id = "overclockApply",
                Status = "requiresConfirmation",
                Reason = "Read-only display of multipliers/clocks/power limits when vendor APIs exist. Apply never runs automatically."
            },
            new CapabilityState
            {
                Id = "overlayInAntiCheat",
                Status = AntiCheatDetector.ShouldWarnOverlay() ? "warn" : "ok",
                Reason = AntiCheatDetector.ShouldWarnOverlay()
                    ? "Active anti-cheat detected — overlays should stay off for protected titles."
                    : "No known anti-cheat process detected right now."
            }
        };
    }

    private static List<string> DetectRgbBridges()
    {
        var names = new Dictionary<string, string[]>(StringComparer.OrdinalIgnoreCase)
        {
            ["ASUS Aura"] = new[] { "LightingService", "ArmouryCrate" },
            ["MSI Mystic Light"] = new[] { "Mystic_Light_Service", "LEDKeeper2" },
            ["Gigabyte RGB Fusion"] = new[] { "RGBFusion", "Aorus" },
            ["Corsair iCUE"] = new[] { "iCUE", "Corsair.Service" },
            ["NZXT CAM"] = new[] { "NZXT CAM", "NZXTCam" },
            ["Razer Chroma"] = new[] { "Razer Synapse", "RzSDKServer" },
            ["SteelSeries GG"] = new[] { "SteelSeriesGG", "SteelSeriesEngine" },
            ["SignalRGB"] = new[] { "SignalRGB" },
        };

        HashSet<string> running;
        try
        {
            running = System.Diagnostics.Process.GetProcesses()
                .Select(p => { try { return p.ProcessName; } finally { p.Dispose(); } })
                .ToHashSet(StringComparer.OrdinalIgnoreCase);
        }
        catch { return new List<string>(); }

        return names
            .Where(kv => kv.Value.Any(v => running.Any(r => r.Contains(v, StringComparison.OrdinalIgnoreCase) || v.Contains(r, StringComparison.OrdinalIgnoreCase))))
            .Select(kv => kv.Key)
            .ToList();
    }
}

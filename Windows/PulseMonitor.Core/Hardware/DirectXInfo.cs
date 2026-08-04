using System.Management;

namespace PulseMonitor.Core.Hardware;

public sealed class DirectXReport
{
    public string? DirectXVersionHint { get; init; }
    public IReadOnlyList<string> FeatureNotes { get; init; } = Array.Empty<string>();
    public IReadOnlyList<(string Name, string? Driver)> Adapters { get; init; } = Array.Empty<(string, string?)>();
    public string HonestyNote { get; init; } =
        "Frame times, present latency, and GPU queue depth require a DXGI/D3D capture session or PIX — not invented from WMI.";
}

public static class DirectXInfo
{
    public static DirectXReport Probe()
    {
        var adapters = new List<(string, string?)>();
        try
        {
            foreach (var obj in WmiHelper.Query("Win32_VideoController"))
            {
                using (obj)
                {
                    adapters.Add((
                        WmiHelper.StringProp(obj, "Name") ?? "GPU",
                        WmiHelper.StringProp(obj, "DriverVersion")));
                }
            }
        }
        catch { }

        // Windows 10/11 ship with DX12; exact feature level needs DXGI factory enumeration in a native bridge.
        return new DirectXReport
        {
            DirectXVersionHint = "DirectX 12 (feature level requires DXGI enumeration bridge)",
            FeatureNotes = new[]
            {
                "Driver versions listed from Win32_VideoController.",
                "Shader cache size is not a stable public WMI property.",
                "Use Game Lab / overlay capture for frame-time charts when a game is attached."
            },
            Adapters = adapters
        };
    }
}

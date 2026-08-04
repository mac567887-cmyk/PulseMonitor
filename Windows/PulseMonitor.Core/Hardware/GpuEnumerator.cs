using System.Management;
using PulseMonitor.Core.Models;

namespace PulseMonitor.Core.Hardware;

public static class GpuEnumerator
{
    public static IReadOnlyList<GpuAdapterInfo> Enumerate()
    {
        var list = new List<GpuAdapterInfo>();
        try
        {
            foreach (var obj in WmiHelper.Query("Win32_VideoController"))
            {
                using (obj)
                {
                    var name = WmiHelper.StringProp(obj, "Name") ?? "Unknown GPU";
                    var vendor = InferVendor(name, WmiHelper.StringProp(obj, "AdapterCompatibility"));
                    var ram = WmiHelper.ULongProp(obj, "AdapterRAM");
                    // AdapterRAM is often capped / wrong for &gt;4GB; still best public WMI field.
                    list.Add(new GpuAdapterInfo
                    {
                        Name = name,
                        DriverVersion = WmiHelper.StringProp(obj, "DriverVersion"),
                        Vendor = vendor,
                        AdapterRamBytes = ram,
                        IsIntegrated = IsIntegrated(name, vendor),
                        UtilizationPercent = null
                    });
                }
            }
        }
        catch
        {
            // WMI unavailable
        }

        return list;
    }

    private static string InferVendor(string name, string? compatibility)
    {
        var hay = $"{name} {compatibility}".ToLowerInvariant();
        if (hay.Contains("nvidia") || hay.Contains("geforce") || hay.Contains("quadro") || hay.Contains("rtx") || hay.Contains("gtx"))
            return "NVIDIA";
        if (hay.Contains("amd") || hay.Contains("radeon") || hay.Contains("ati "))
            return "AMD";
        if (hay.Contains("intel") || hay.Contains("arc") || hay.Contains("uhd") || hay.Contains("iris"))
            return "Intel";
        return compatibility ?? "Unknown";
    }

    private static bool IsIntegrated(string name, string vendor)
    {
        var n = name.ToLowerInvariant();
        if (n.Contains("uhd") || n.Contains("iris") || n.Contains("radeon graphics") && !n.Contains("rx"))
            return true;
        if (vendor == "Intel" && !n.Contains("arc"))
            return true;
        return false;
    }
}

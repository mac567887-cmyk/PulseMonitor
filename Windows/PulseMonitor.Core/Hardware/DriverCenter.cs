using System.Management;

namespace PulseMonitor.Core.Hardware;

public sealed class DriverEntry
{
    public required string DeviceName { get; init; }
    public required string Category { get; init; }
    public string? DriverVersion { get; init; }
    public string? Manufacturer { get; init; }
    public DateTime? DriverDate { get; init; }
}

public static class DriverCenter
{
    public static IReadOnlyList<DriverEntry> EnumerateKeyDrivers()
    {
        var list = new List<DriverEntry>();
        try
        {
            foreach (var obj in WmiHelper.Query("Win32_PnPSignedDriver"))
            {
                using (obj)
                {
                    var name = WmiHelper.StringProp(obj, "DeviceName") ?? "Device";
                    var cls = WmiHelper.StringProp(obj, "DeviceClass") ?? "";
                    var category = Classify(cls, name);
                    if (category is null) continue;
                    DateTime? date = null;
                    var rawDate = WmiHelper.StringProp(obj, "DriverDate");
                    if (!string.IsNullOrWhiteSpace(rawDate) && DateTime.TryParse(rawDate, out var parsed))
                        date = parsed;

                    list.Add(new DriverEntry
                    {
                        DeviceName = name,
                        Category = category,
                        DriverVersion = WmiHelper.StringProp(obj, "DriverVersion"),
                        Manufacturer = WmiHelper.StringProp(obj, "Manufacturer"),
                        DriverDate = date
                    });
                }
            }
        }
        catch { }

        return list
            .GroupBy(d => d.DeviceName + d.Category)
            .Select(g => g.First())
            .OrderBy(d => d.Category)
            .ThenBy(d => d.DeviceName)
            .Take(120)
            .ToList();
    }

    private static string? Classify(string deviceClass, string name)
    {
        var c = deviceClass.ToLowerInvariant();
        var n = name.ToLowerInvariant();
        if (c.Contains("display") || n.Contains("nvidia") || n.Contains("radeon") || n.Contains("geforce") || n.Contains("intel arc"))
            return "GPU";
        if (c.Contains("net") || n.Contains("wifi") || n.Contains("ethernet") || n.Contains("wireless"))
            return "Network";
        if (c.Contains("media") || n.Contains("audio") || n.Contains("realtek") || n.Contains("sound"))
            return "Audio";
        if (c.Contains("monitor") || n.Contains("monitor"))
            return "Monitor";
        if (n.Contains("chipset") || n.Contains("smbus") || n.Contains("lpc") || n.Contains("me interface"))
            return "Chipset";
        if (n.Contains("firmware") || n.Contains("bios"))
            return "Firmware";
        return null;
    }
}

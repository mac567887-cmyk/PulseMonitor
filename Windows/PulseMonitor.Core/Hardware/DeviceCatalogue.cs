using System.Management;

namespace PulseMonitor.Core.Hardware;

public sealed class DeviceRow
{
    public required string Category { get; init; }
    public required string Name { get; init; }
    public string? Manufacturer { get; init; }
    public string? Status { get; init; }
}

/// <summary>
/// USB, Bluetooth, monitors, audio, and PCI devices via WMI / PnP.
/// </summary>
public static class DeviceCatalogue
{
    public static IReadOnlyList<DeviceRow> Enumerate()
    {
        var list = new List<DeviceRow>();
        list.AddRange(QueryPnP("USB"));
        list.AddRange(QueryPnP("Bluetooth"));
        list.AddRange(QueryPnP("Monitor"));
        list.AddRange(QueryClass("Win32_SoundDevice", "Audio"));
        list.AddRange(QueryClass("Win32_IDEController", "Storage Controller"));
        list.AddRange(QueryClass("Win32_SCSIController", "Storage Controller"));
        list.AddRange(QueryPnP("Net")); // Wi-Fi / Ethernet adapters often under Net
        return list
            .GroupBy(d => d.Category + "|" + d.Name, StringComparer.OrdinalIgnoreCase)
            .Select(g => g.First())
            .OrderBy(d => d.Category)
            .ThenBy(d => d.Name)
            .Take(200)
            .ToList();
    }

    private static IEnumerable<DeviceRow> QueryClass(string wmiClass, string category, string prefer = "Name")
    {
        var rows = new List<DeviceRow>();
        try
        {
            foreach (var obj in WmiHelper.Query(wmiClass))
            {
                using (obj)
                {
                    var name = WmiHelper.StringProp(obj, prefer)
                        ?? WmiHelper.StringProp(obj, "Name")
                        ?? WmiHelper.StringProp(obj, "Caption");
                    if (string.IsNullOrWhiteSpace(name)) continue;
                    rows.Add(new DeviceRow
                    {
                        Category = category,
                        Name = name,
                        Manufacturer = WmiHelper.StringProp(obj, "Manufacturer"),
                        Status = WmiHelper.StringProp(obj, "Status")
                    });
                }
            }
        }
        catch { }
        return rows;
    }

    private static IEnumerable<DeviceRow> QueryPnP(string classHint)
    {
        var rows = new List<DeviceRow>();
        try
        {
            foreach (var obj in WmiHelper.Query("Win32_PnPEntity"))
            {
                using (obj)
                {
                    var pnpClass = WmiHelper.StringProp(obj, "PNPClass") ?? "";
                    var name = WmiHelper.StringProp(obj, "Name") ?? "";
                    if (!pnpClass.Equals(classHint, StringComparison.OrdinalIgnoreCase)
                        && !name.Contains(classHint, StringComparison.OrdinalIgnoreCase))
                        continue;
                    if (string.IsNullOrWhiteSpace(name)) continue;
                    rows.Add(new DeviceRow
                    {
                        Category = classHint,
                        Name = name,
                        Manufacturer = WmiHelper.StringProp(obj, "Manufacturer"),
                        Status = WmiHelper.StringProp(obj, "Status")
                    });
                }
            }
        }
        catch { }
        return rows;
    }
}

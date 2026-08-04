using System.Management;

namespace PulseMonitor.Core.Hardware;

internal static class WmiHelper
{
    public static IEnumerable<ManagementObject> Query(string wmiClass, string? where = null)
    {
        var query = where is null
            ? $"SELECT * FROM {wmiClass}"
            : $"SELECT * FROM {wmiClass} WHERE {where}";
        using var searcher = new ManagementObjectSearcher(query);
        foreach (ManagementObject obj in searcher.Get())
            yield return obj;
    }

    public static string? StringProp(ManagementBaseObject obj, string name)
        => obj[name]?.ToString();

    public static ulong? ULongProp(ManagementBaseObject obj, string name)
    {
        try
        {
            var v = obj[name];
            if (v is null) return null;
            return Convert.ToUInt64(v);
        }
        catch
        {
            return null;
        }
    }

    public static double? DoubleProp(ManagementBaseObject obj, string name)
    {
        try
        {
            var v = obj[name];
            if (v is null) return null;
            return Convert.ToDouble(v);
        }
        catch
        {
            return null;
        }
    }
}

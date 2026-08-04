using System.Management;

namespace PulseMonitor.Core.Hardware;

public static class CpuIdentity
{
    public static string? Brand()
    {
        try
        {
            foreach (var obj in WmiHelper.Query("Win32_Processor"))
            {
                using (obj)
                {
                    return WmiHelper.StringProp(obj, "Name")?.Trim();
                }
            }
        }
        catch { }
        return null;
    }

    public static string? SystemModel()
    {
        try
        {
            foreach (var obj in WmiHelper.Query("Win32_ComputerSystem"))
            {
                using (obj)
                {
                    var manufacturer = WmiHelper.StringProp(obj, "Manufacturer");
                    var model = WmiHelper.StringProp(obj, "Model");
                    return $"{manufacturer} {model}".Trim();
                }
            }
        }
        catch { }
        return null;
    }

    /// <summary>
    /// ThermalZone temperature is often unavailable or requires admin; returns null when absent.
    /// Values from MSAcpi_ThermalZoneTemperature are Kelvin * 10.
    /// </summary>
    public static double? TryThermalZoneCelsius()
    {
        try
        {
            using var searcher = new ManagementObjectSearcher(
                @"root\WMI",
                "SELECT * FROM MSAcpi_ThermalZoneTemperature");
            foreach (ManagementObject obj in searcher.Get())
            {
                using (obj)
                {
                    var raw = WmiHelper.DoubleProp(obj, "CurrentTemperature");
                    if (raw is null) continue;
                    return (raw.Value / 10.0) - 273.15;
                }
            }
        }
        catch
        {
            // class often access-denied without elevation
        }
        return null;
    }
}

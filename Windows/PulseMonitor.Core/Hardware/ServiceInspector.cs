using System.Management;
using System.ServiceProcess;
using PulseMonitor.Core.Models;

namespace PulseMonitor.Core.Hardware;

public static class ServiceInspector
{
    public static IReadOnlyList<ServiceRow> ListServices(int limit = 200)
    {
        try
        {
            return ServiceController.GetServices()
                .OrderBy(s => s.ServiceName)
                .Take(limit)
                .Select(s =>
                {
                    using (s)
                    {
                        return new ServiceRow
                        {
                            Name = s.ServiceName,
                            DisplayName = s.DisplayName,
                            Status = s.Status.ToString(),
                            StartType = s.StartType.ToString()
                        };
                    }
                })
                .ToList();
        }
        catch
        {
            return Array.Empty<ServiceRow>();
        }
    }

    public static IReadOnlyList<(string Name, string Command)> StartupCommands()
    {
        var results = new List<(string, string)>();
        try
        {
            foreach (var obj in WmiHelper.Query("Win32_StartupCommand"))
            {
                using (obj)
                {
                    var name = WmiHelper.StringProp(obj, "Name") ?? "startup";
                    var command = WmiHelper.StringProp(obj, "Command") ?? "";
                    results.Add((name, command));
                }
            }
        }
        catch { }
        return results;
    }
}

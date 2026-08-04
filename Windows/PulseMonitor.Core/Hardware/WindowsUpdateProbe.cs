namespace PulseMonitor.Core.Hardware;

public sealed class UpdateStatus
{
    public required string Summary { get; init; }
    public IReadOnlyList<string> Notes { get; init; } = Array.Empty<string>();
}

/// <summary>
/// Windows Update COM (WUApiLib) is heavy and often blocked in sandboxes.
/// This probe reports how to inspect updates honestly without inventing pending counts.
/// </summary>
public static class WindowsUpdateProbe
{
    public static UpdateStatus Probe()
    {
        var notes = new List<string>
        {
            "Open Settings → Windows Update for pending / failed / security updates.",
            "Driver updates may appear under Optional updates or OEM utilities.",
            "Rollback history: Settings → Windows Update → Update history → Uninstall updates.",
            "PulseMonitor does not silently change Windows Update policies."
        };

        // Soft signal: UsoClient / Windows Update service state
        try
        {
            var wu = ServiceInspector.ListServices(500)
                .FirstOrDefault(s => s.Name.Equals("wuauserv", StringComparison.OrdinalIgnoreCase));
            if (wu is not null)
                notes.Insert(0, $"Windows Update service (wuauserv) is {wu.Status} / {wu.StartType}.");
        }
        catch { }

        return new UpdateStatus
        {
            Summary = "Windows Update catalogue requires WUApiLib session — UI shows guidance until the optional update bridge is enabled.",
            Notes = notes
        };
    }
}

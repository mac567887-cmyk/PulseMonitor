using System.Diagnostics.Eventing.Reader;
using PulseMonitor.Core.Models;

namespace PulseMonitor.Core.Hardware;

/// <summary>
/// Reads Windows Event Logs via Event Log API and summarizes in plain English.
/// Requires appropriate permissions; failures return empty findings (no invention).
/// </summary>
public static class EventLogAnalyzer
{
    public static IReadOnlyList<EventFinding> SummarizeRecent(int maxEvents = 80)
    {
        var findings = new List<EventFinding>();
        Scan("System", maxEvents / 2, findings);
        Scan("Application", maxEvents / 2, findings);
        return findings
            .OrderByDescending(f => f.TimeCreated ?? DateTimeOffset.MinValue)
            .Take(40)
            .ToList();
    }

    private static void Scan(string logName, int max, List<EventFinding> into)
    {
        try
        {
            var query = new EventLogQuery(logName, PathType.LogName, "*[System[(Level=1 or Level=2 or Level=3)]]");
            using var reader = new EventLogReader(query);
            var count = 0;
            for (var rec = reader.ReadEvent(); rec is not null && count < max; rec = reader.ReadEvent())
            {
                using (rec)
                {
                    var id = rec.Id;
                    var provider = rec.ProviderName ?? "Unknown";
                    var level = rec.LevelDisplayName ?? "Warning";
                    var message = SafeMessage(rec);
                    var category = Categorize(provider, id, message);
                    into.Add(new EventFinding
                    {
                        Category = category,
                        Severity = NormalizeSeverity(level),
                        Title = $"{provider} ({id})",
                        Summary = Truncate(message, 280),
                        TimeCreated = rec.TimeCreated,
                        Recommendations = Recommend(category)
                    });
                    count++;
                }
            }
        }
        catch
        {
            // access denied or log missing
        }
    }

    private static string Categorize(string provider, int id, string message)
    {
        var hay = $"{provider} {message}".ToLowerInvariant();
        if (hay.Contains("bugcheck") || hay.Contains("blue screen") || id is 41 or 1001)
            return "BSOD / Unexpected Shutdown";
        if (hay.Contains("disk") || hay.Contains("ntfs") || hay.Contains("storahci") || hay.Contains("nvme"))
            return "Disk";
        if (hay.Contains("display") || hay.Contains("nvlddmkm") || hay.Contains("amdkmdag") || hay.Contains("dxgkrnl"))
            return "Driver / GPU";
        if (hay.Contains("power") || hay.Contains("kernel-power") || id == 41)
            return "Power";
        if (hay.Contains("kernel"))
            return "Kernel";
        return "Application / System";
    }

    private static IReadOnlyList<string> Recommend(string category) => category switch
    {
        "BSOD / Unexpected Shutdown" => new[]
        {
            "Open PulseMonitor → BSOD Analyzer and point it at %SystemRoot%\\Minidump.",
            "Note the faulting driver before updating graphics or chipset drivers.",
            "Check Event Viewer Kernel-Power 41 and BugCheck 1001 for correlation."
        },
        "Disk" => new[]
        {
            "Run `chkdsk` only after backing up critical data.",
            "Check SMART health in Storage Analysis before replacing drives."
        },
        "Driver / GPU" => new[]
        {
            "Compare the GPU driver version in Driver Center with the vendor’s WHQL release.",
            "Disable experimental overlays if crashes coincide with games."
        },
        "Power" => new[]
        {
            "Unexpected shutdowns often indicate power loss, overheating, or forced reboot — not always a software bug."
        },
        _ => new[] { "Review the full event details in Event Viewer before changing system settings." }
    };

    private static string NormalizeSeverity(string level)
    {
        var l = level.ToLowerInvariant();
        if (l.Contains("critical") || l.Contains("error")) return "critical";
        if (l.Contains("warn")) return "warning";
        return "info";
    }

    private static string SafeMessage(EventRecord rec)
    {
        try { return rec.FormatDescription() ?? "(no description)"; }
        catch { return "(description unavailable)"; }
    }

    private static string Truncate(string s, int n)
        => s.Length <= n ? s : s[..(n - 1)] + "…";
}

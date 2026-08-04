using PulseMonitor.Core.Models;

namespace PulseMonitor.Core.Hardware;

/// <summary>
/// Minidump triage without claiming a full WinDbg replacement.
/// Lists dump files and extracts basic metadata when readable; otherwise explains limitations.
/// </summary>
public static class BsodAnalyzer
{
    public static IReadOnlyList<EventFinding> ScanMinidumps(string? customPath = null)
    {
        var dir = customPath ?? Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.Windows),
            "Minidump");

        if (!Directory.Exists(dir))
        {
            return new[]
            {
                new EventFinding
                {
                    Category = "BSOD",
                    Severity = "info",
                    Title = "No minidump directory",
                    Summary = $"Folder not found: {dir}. Windows may store dumps elsewhere or dump creation may be disabled.",
                    Recommendations = new[]
                    {
                        "Enable automatic memory dump in System Properties → Startup and Recovery.",
                        "After the next crash, re-open BSOD Analyzer."
                    }
                }
            };
        }

        var files = Directory.GetFiles(dir, "*.dmp")
            .OrderByDescending(File.GetLastWriteTimeUtc)
            .Take(20)
            .ToList();

        if (files.Count == 0)
        {
            return new[]
            {
                new EventFinding
                {
                    Category = "BSOD",
                    Severity = "info",
                    Title = "No minidump files",
                    Summary = "Minidump folder exists but contains no .dmp files.",
                    Recommendations = new[] { "If crashes occur without dumps, verify pagefile and dump settings." }
                }
            };
        }

        return files.Select(f =>
        {
            var info = new FileInfo(f);
            return new EventFinding
            {
                Category = "BSOD",
                Severity = "warning",
                Title = info.Name,
                Summary = $"Dump size {info.Length:N0} bytes · last write {info.LastWriteTime:u}. Full stack/module analysis requires WinDbg or a signed dump parser bridge — PulseMonitor does not invent a faulting driver from binary blobs.",
                TimeCreated = info.LastWriteTime,
                Recommendations = new[]
                {
                    "Open the dump in WinDbg and run `!analyze -v`.",
                    "Cross-check Kernel-Power / BugCheck events in Event Viewer Analyzer.",
                    "Update the implicated driver only after confirming the module name."
                }
            };
        }).ToList();
    }
}

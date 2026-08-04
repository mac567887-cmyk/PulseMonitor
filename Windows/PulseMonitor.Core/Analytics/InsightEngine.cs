using PulseMonitor.Core.Hardware;
using PulseMonitor.Core.Models;

namespace PulseMonitor.Core.Analytics;

public static class InsightEngine
{
    public static IReadOnlyList<EventFinding> Analyze(MetricSnapshot metrics, IReadOnlyList<ProcessRow> processes)
    {
        var findings = new List<EventFinding>();

        if (metrics.CpuPercent >= 85)
        {
            var top = processes.FirstOrDefault();
            findings.Add(new EventFinding
            {
                Category = "CPU",
                Severity = "warning",
                Title = "High CPU utilization",
                Summary = top is null
                    ? $"CPU is at {metrics.CpuPercent:0}%."
                    : $"CPU is at {metrics.CpuPercent:0}%. Top process: {top.Name} ({top.CpuPercent:0.0}%).",
                Recommendations = new[] { "Inspect Process Explorer before ending tasks.", "Check Windows Update / Search Indexer if idle." }
            });
        }

        if (metrics.MemoryPercent >= 90)
        {
            findings.Add(new EventFinding
            {
                Category = "Memory",
                Severity = "warning",
                Title = "Memory pressure",
                Summary = $"Working set pressure at {metrics.MemoryPercent:0}% of physical RAM.",
                Recommendations = new[] { "Close unused Chromium/Electron apps.", "Review Startup entries in Windows Services module." }
            });
        }

        foreach (var p in processes.Take(25))
        {
            var n = p.Name.ToLowerInvariant();
            if (n.Contains("discord") && p.CpuPercent > 8)
            {
                findings.Add(new EventFinding
                {
                    Category = "GPU / App",
                    Severity = "info",
                    Title = "Discord may be using hardware acceleration",
                    Summary = "Discord is active with elevated CPU. Hardware acceleration can consume unnecessary GPU resources on some systems.",
                    Recommendations = new[] { "In Discord Settings → Advanced, try disabling Hardware Acceleration if GPU memory is tight." }
                });
            }
            if (n.Contains("nvcontainer") || n.Contains("nvidia share") || n.Contains("shadowplay"))
            {
                findings.Add(new EventFinding
                {
                    Category = "GPU",
                    Severity = "info",
                    Title = "NVIDIA capture stack is running",
                    Summary = "NVIDIA ShadowPlay / overlay components can reduce available VRAM while idle recording is enabled.",
                    Recommendations = new[] { "Disable Instant Replay in GeForce Experience when not recording." }
                });
            }
            if (n.Contains("searchindexer") && p.CpuPercent > 10)
            {
                findings.Add(new EventFinding
                {
                    Category = "Storage",
                    Severity = "info",
                    Title = "Windows Search Indexing is busy",
                    Summary = "SearchIndexer is elevating CPU and can cause excess SSD writes during large index rebuilds.",
                    Recommendations = new[] { "Pause indexing briefly from Windows Search settings if on battery or during creative work." }
                });
            }
            if (n.Contains("tiworker") || n.Contains("usoclient") || n.Contains("wuauclt"))
            {
                if (p.CpuPercent > 12)
                {
                    findings.Add(new EventFinding
                    {
                        Category = "Windows Update",
                        Severity = "info",
                        Title = "Background Windows Update activity",
                        Summary = $"{p.Name} is using {p.CpuPercent:0}% CPU — typical during update download/install.",
                        Recommendations = new[] { "Prefer Active Hours / pause updates rather than killing TiWorker." }
                    });
                }
            }
        }

        if (AntiCheatDetector.ShouldWarnOverlay())
        {
            findings.Add(new EventFinding
            {
                Category = "Anti-Cheat",
                Severity = "warning",
                Title = "Anti-cheat is active",
                Summary = "Known anti-cheat software is running. Overlays can trigger false positives or be blocked.",
                Recommendations = new[] { "Keep PulseMonitor overlay disabled for protected games.", "PulseMonitor never injects into game processes." }
            });
        }

        return findings
            .GroupBy(f => f.Title)
            .Select(g => g.First())
            .Take(12)
            .ToList();
    }

    public static double HealthScore(MetricSnapshot m, IReadOnlyList<EventFinding> findings)
    {
        double score = 100;
        score -= Math.Clamp((m.CpuPercent - 50) * 0.4, 0, 25);
        score -= Math.Clamp((m.MemoryPercent - 60) * 0.5, 0, 25);
        if (m.GpuPercent is double g)
            score -= Math.Clamp((g - 70) * 0.3, 0, 15);
        score -= findings.Count(f => f.Severity == "critical") * 12;
        score -= findings.Count(f => f.Severity == "warning") * 5;
        return Math.Clamp(score, 0, 100);
    }
}

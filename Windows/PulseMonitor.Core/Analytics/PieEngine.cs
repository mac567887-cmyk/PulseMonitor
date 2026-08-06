namespace PulseMonitor.Core.Analytics;

/// Lightweight Windows-side PIE façade mirroring macOS Athena contracts.
/// Predictions are linear estimates; unavailable sensors stay null.
public static class PieEngine
{
    public sealed record PieInsight(string Title, string Summary, string Why, double Confidence, string Category);

    public static IReadOnlyList<PieInsight> LiveInsights(
        Models.MetricSnapshot metrics,
        IReadOnlyList<Models.ProcessRow> processes)
    {
        var list = new List<PieInsight>();
        var top = processes.OrderByDescending(p => p.CpuPercent).FirstOrDefault();
        if (top is not null && top.CpuPercent >= 20)
        {
            list.Add(new PieInsight(
                "CPU explanation",
                $"{top.Name} is using {top.CpuPercent:0}% CPU.",
                $"System CPU is {metrics.CpuPercent:0}% while {top.Name} leads the process table.",
                Math.Min(98, 55 + top.CpuPercent * 0.4),
                "cpu"));
        }

        if (metrics.MemoryPercent >= 90)
        {
            list.Add(new PieInsight(
                "Memory pressure",
                $"Memory is at {metrics.MemoryPercent:0}%.",
                "GlobalMemoryStatusEx reported elevated commit load.",
                90,
                "memory"));
        }

        list.AddRange(InsightEngine.Analyze(metrics, processes).Select(f =>
            new PieInsight(f.Title, f.Summary, f.Summary, f.Severity == "critical" ? 90 : 75, f.Category)));

        return list
            .GroupBy(i => i.Title)
            .Select(g => g.First())
            .Take(10)
            .ToList();
    }

    public static string Mood(Models.MetricSnapshot m, double health)
    {
        if (m.ThermalState is "Critical" or "Serious") return "🟠 Thermal Stress";
        if (m.CpuPercent >= 85 || (m.GpuPercent ?? 0) >= 90) return "🟡 Under Heavy Load";
        if (m.MemoryPercent >= 92) return "🟠 Memory Pressure";
        if (health >= 85 && m.CpuPercent < 30) return "🟢 Excellent";
        return health >= 70 ? "🟢 Excellent" : "🟡 Under Heavy Load";
    }
}

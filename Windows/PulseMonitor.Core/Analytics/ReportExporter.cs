using System.Text.Json;
using System.Text.Json.Serialization;
using PulseMonitor.Core.Hardware;
using PulseMonitor.Core.Models;

namespace PulseMonitor.Core.Analytics;

public static class ReportExporter
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
    };

    public static DiagnosticReport Build(MetricSnapshot metrics, IReadOnlyList<ProcessRow> processes)
    {
        var findings = InsightEngine.Analyze(metrics, processes);
        var score = InsightEngine.HealthScore(metrics, findings);
        var narrative = score >= 85
            ? "System looks healthy. No urgent action required."
            : score >= 65
                ? "Moderate pressure detected. Review the findings below."
                : "Elevated resource pressure or warnings — investigate before heavy workloads.";

        return new DiagnosticReport
        {
            SchemaVersion = "4.0.0",
            Platform = "Windows",
            GeneratedAt = DateTimeOffset.UtcNow,
            Hardware = new HardwareInfo
            {
                ModelIdentifier = CpuIdentity.SystemModel(),
                CpuBrand = CpuIdentity.Brand(),
                GpuName = metrics.GpuName,
                MemoryBytes = metrics.MemoryTotalBytes,
                OsVersion = Environment.OSVersion.VersionString
            },
            Metrics = new ReportMetrics
            {
                CpuPercent = metrics.CpuPercent,
                GpuPercent = metrics.GpuPercent,
                MemoryPercent = metrics.MemoryPercent,
                ThermalState = metrics.ThermalState,
                BatteryPercent = metrics.BatteryPercent,
                DiskReadBps = metrics.DiskReadBps,
                DiskWriteBps = metrics.DiskWriteBps,
                NetworkInBps = metrics.NetworkInBps,
                NetworkOutBps = metrics.NetworkOutBps
            },
            Analysis = new ReportAnalysis
            {
                OverallHealthScore = score,
                Narrative = narrative,
                Findings = findings
            },
            Recommendations = findings.SelectMany(f => f.Recommendations).Distinct().Take(10).ToList()
        };
    }

    public static string ToJson(DiagnosticReport report)
        => JsonSerializer.Serialize(report, JsonOptions);

    public static void WriteJson(DiagnosticReport report, string path)
        => File.WriteAllText(path, ToJson(report));
}

namespace PulseMonitor.Core.Models;

public sealed class MetricSnapshot
{
    public required DateTimeOffset Timestamp { get; init; }
    public double CpuPercent { get; init; }
    public IReadOnlyList<double> CpuPerCorePercent { get; init; } = Array.Empty<double>();
    public double? CpuTemperatureC { get; init; }
    public double MemoryPercent { get; init; }
    public ulong MemoryUsedBytes { get; init; }
    public ulong MemoryTotalBytes { get; init; }
    public double? GpuPercent { get; init; }
    public string? GpuName { get; init; }
    public ulong? GpuDedicatedMemoryBytes { get; init; }
    public double? GpuTemperatureC { get; init; }
    public double DiskReadBps { get; init; }
    public double DiskWriteBps { get; init; }
    public double NetworkInBps { get; init; }
    public double NetworkOutBps { get; init; }
    public double? BatteryPercent { get; init; }
    public bool? BatteryCharging { get; init; }
    public string ThermalState { get; init; } = "Nominal";
    public IReadOnlyList<GpuAdapterInfo> Gpus { get; init; } = Array.Empty<GpuAdapterInfo>();
    public IReadOnlyDictionary<string, string> Unavailable { get; init; }
        = new Dictionary<string, string>();
}

public sealed class GpuAdapterInfo
{
    public required string Name { get; init; }
    public string? DriverVersion { get; init; }
    public string? Vendor { get; init; }
    public ulong? AdapterRamBytes { get; init; }
    public bool IsIntegrated { get; init; }
    public double? UtilizationPercent { get; init; }
}

public sealed class ProcessRow
{
    public int Pid { get; init; }
    public required string Name { get; init; }
    public double CpuPercent { get; init; }
    public long WorkingSetBytes { get; init; }
}

public sealed class ServiceRow
{
    public required string Name { get; init; }
    public required string DisplayName { get; init; }
    public required string Status { get; init; }
    public required string StartType { get; init; }
}

public sealed class EventFinding
{
    public required string Category { get; init; }
    public required string Severity { get; init; }
    public required string Title { get; init; }
    public required string Summary { get; init; }
    public DateTimeOffset? TimeCreated { get; init; }
    public IReadOnlyList<string> Recommendations { get; init; } = Array.Empty<string>();
}

public sealed class CapabilityState
{
    public required string Id { get; init; }
    public required string Status { get; init; }
    public string? Reason { get; init; }
}

public sealed class DiagnosticReport
{
    public string SchemaVersion { get; init; } = "4.0.0";
    public string Platform { get; init; } = "Windows";
    public required DateTimeOffset GeneratedAt { get; init; }
    public required HardwareInfo Hardware { get; init; }
    public required ReportMetrics Metrics { get; init; }
    public required ReportAnalysis Analysis { get; init; }
    public IReadOnlyList<string> Recommendations { get; init; } = Array.Empty<string>();
}

public sealed class HardwareInfo
{
    public string? ModelIdentifier { get; init; }
    public string? CpuBrand { get; init; }
    public string? GpuName { get; init; }
    public ulong? MemoryBytes { get; init; }
    public required string OsVersion { get; init; }
}

public sealed class ReportMetrics
{
    public double CpuPercent { get; init; }
    public double? GpuPercent { get; init; }
    public double MemoryPercent { get; init; }
    public required string ThermalState { get; init; }
    public double? BatteryPercent { get; init; }
    public double DiskReadBps { get; init; }
    public double DiskWriteBps { get; init; }
    public double NetworkInBps { get; init; }
    public double NetworkOutBps { get; init; }
}

public sealed class ReportAnalysis
{
    public double OverallHealthScore { get; init; }
    public required string Narrative { get; init; }
    public IReadOnlyList<EventFinding> Findings { get; init; } = Array.Empty<EventFinding>();
}

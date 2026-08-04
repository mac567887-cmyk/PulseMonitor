using PulseMonitor.Core.Models;

namespace PulseMonitor.Core.Hardware;

public sealed class MetricsCollector : IDisposable
{
    private readonly PdhSampler _pdh = new();
    private DateTimeOffset _lastGpuSample = DateTimeOffset.MinValue;
    private double? _lastGpuPercent;

    public MetricSnapshot Sample()
    {
        _pdh.EnsureInitialized();
        // PDH needs a second tick for meaningful rates.
        Thread.Sleep(120);

        var cpu = _pdh.SampleCpuTotal() ?? 0;
        var cores = _pdh.SampleCpuCores();
        var (memPct, memUsed, memTotal) = MemorySampler.Sample();
        var (diskR, diskW) = _pdh.SampleDisk();
        var (netIn, netOut) = _pdh.SampleNetwork();
        var (battPct, battCharge) = BatterySampler.Sample();
        var gpus = GpuEnumerator.Enumerate();
        var unavailable = new Dictionary<string, string>();

        double? gpuPct = null;
        if ((DateTimeOffset.UtcNow - _lastGpuSample).TotalSeconds >= 1)
        {
            _lastGpuPercent = _pdh.SampleGpuEngineUtilization();
            _lastGpuSample = DateTimeOffset.UtcNow;
        }
        gpuPct = _lastGpuPercent;
        if (gpuPct is null)
            unavailable["gpuPercent"] = "GPU Engine performance counters unavailable on this system.";

        var temp = CpuIdentity.TryThermalZoneCelsius();
        if (temp is null)
            unavailable["cpuTemperature"] = "ACPI thermal zone temperature requires elevation or is not exposed.";

        unavailable["gpuTemperature"] = "GPU temperature needs vendor NVAPI/ADL/IGCL; not invented via WMI.";
        unavailable["rayTracingUtilization"] = "No public OS counter for RT utilization.";
        unavailable["tensorCoreUtilization"] = "No public OS counter for tensor utilization.";
        unavailable["psuTelemetry"] = "PSU sensors are not exposed by Windows APIs.";

        return new MetricSnapshot
        {
            Timestamp = DateTimeOffset.UtcNow,
            CpuPercent = Math.Clamp(cpu, 0, 100),
            CpuPerCorePercent = cores,
            CpuTemperatureC = temp,
            MemoryPercent = memPct,
            MemoryUsedBytes = memUsed,
            MemoryTotalBytes = memTotal,
            GpuPercent = gpuPct,
            GpuName = gpus.FirstOrDefault()?.Name,
            GpuDedicatedMemoryBytes = gpus.FirstOrDefault(g => !g.IsIntegrated)?.AdapterRamBytes
                ?? gpus.FirstOrDefault()?.AdapterRamBytes,
            GpuTemperatureC = null,
            DiskReadBps = diskR,
            DiskWriteBps = diskW,
            NetworkInBps = netIn,
            NetworkOutBps = netOut,
            BatteryPercent = battPct,
            BatteryCharging = battCharge,
            ThermalState = InferThermal(temp, cpu),
            Gpus = gpus,
            Unavailable = unavailable
        };
    }

    private static string InferThermal(double? tempC, double cpu)
    {
        if (tempC is >= 95) return "Critical";
        if (tempC is >= 85) return "Serious";
        if (tempC is >= 75 || cpu >= 95) return "Fair";
        return "Nominal";
    }

    public void Dispose() => _pdh.Dispose();
}

using System.Diagnostics;

namespace PulseMonitor.Core.Hardware;

/// <summary>
/// Thin wrapper around Windows Performance Counters (PDH-backed).
/// Counters that are missing on a machine return null — never fabricated.
/// </summary>
public sealed class PdhSampler : IDisposable
{
    private PerformanceCounter? _cpuTotal;
    private PerformanceCounter? _diskRead;
    private PerformanceCounter? _diskWrite;
    private PerformanceCounter? _netIn;
    private PerformanceCounter? _netOut;
    private readonly List<PerformanceCounter> _cpuCores = new();
    private bool _initialized;

    public void EnsureInitialized()
    {
        if (_initialized) return;
        _initialized = true;

        Try(() =>
        {
            _cpuTotal = new PerformanceCounter("Processor", "% Processor Time", "_Total", true);
            _ = _cpuTotal.NextValue();
        });

        Try(() =>
        {
            var cat = new PerformanceCounterCategory("Processor Information");
            foreach (var instance in cat.GetInstanceNames().Where(n => n.Contains(",")).OrderBy(n => n))
            {
                var c = new PerformanceCounter("Processor Information", "% Processor Time", instance, true);
                _ = c.NextValue();
                _cpuCores.Add(c);
            }
        });

        if (_cpuCores.Count == 0)
        {
            Try(() =>
            {
                var cat = new PerformanceCounterCategory("Processor");
                foreach (var instance in cat.GetInstanceNames().Where(n => n != "_Total").OrderBy(n => n))
                {
                    var c = new PerformanceCounter("Processor", "% Processor Time", instance, true);
                    _ = c.NextValue();
                    _cpuCores.Add(c);
                }
            });
        }

        Try(() =>
        {
            _diskRead = new PerformanceCounter("PhysicalDisk", "Disk Read Bytes/sec", "_Total", true);
            _diskWrite = new PerformanceCounter("PhysicalDisk", "Disk Write Bytes/sec", "_Total", true);
            _ = _diskRead.NextValue();
            _ = _diskWrite.NextValue();
        });

        Try(() =>
        {
            // Aggregate first active network interface with non-zero traffic potential.
            var cat = new PerformanceCounterCategory("Network Interface");
            var first = cat.GetInstanceNames().FirstOrDefault();
            if (first is null) return;
            _netIn = new PerformanceCounter("Network Interface", "Bytes Received/sec", first, true);
            _netOut = new PerformanceCounter("Network Interface", "Bytes Sent/sec", first, true);
            _ = _netIn.NextValue();
            _ = _netOut.NextValue();
        });
    }

    public double? SampleCpuTotal()
    {
        EnsureInitialized();
        return TryRead(_cpuTotal);
    }

    public IReadOnlyList<double> SampleCpuCores()
    {
        EnsureInitialized();
        if (_cpuCores.Count == 0) return Array.Empty<double>();
        return _cpuCores.Select(c => Math.Clamp(c.NextValue(), 0, 100)).ToArray();
    }

    public (double read, double write) SampleDisk()
    {
        EnsureInitialized();
        return (TryRead(_diskRead) ?? 0, TryRead(_diskWrite) ?? 0);
    }

    public (double inbound, double outbound) SampleNetwork()
    {
        EnsureInitialized();
        return (TryRead(_netIn) ?? 0, TryRead(_netOut) ?? 0);
    }

    /// <summary>
    /// GPU engine utilization via "GPU Engine" counters when present (WDDM).
    /// Returns null when the counter category is unavailable.
    /// </summary>
    public double? SampleGpuEngineUtilization()
    {
        try
        {
            if (!PerformanceCounterCategory.Exists("GPU Engine"))
                return null;

            var cat = new PerformanceCounterCategory("GPU Engine");
            double sum = 0;
            var count = 0;
            foreach (var instance in cat.GetInstanceNames())
            {
                if (!instance.Contains("engtype_3D", StringComparison.OrdinalIgnoreCase)
                    && !instance.Contains("engtype_Graphics", StringComparison.OrdinalIgnoreCase))
                    continue;
                try
                {
                    using var c = new PerformanceCounter("GPU Engine", "Utilization Percentage", instance, true);
                    sum += c.NextValue();
                    count++;
                }
                catch
                {
                    // skip instance
                }
            }

            if (count == 0) return null;
            // First sample after creation is often 0; callers should sample twice across ticks.
            return Math.Clamp(sum, 0, 100);
        }
        catch
        {
            return null;
        }
    }

    private static double? TryRead(PerformanceCounter? counter)
    {
        if (counter is null) return null;
        try { return Math.Max(0, counter.NextValue()); }
        catch { return null; }
    }

    private static void Try(Action action)
    {
        try { action(); } catch { /* counter category missing */ }
    }

    public void Dispose()
    {
        _cpuTotal?.Dispose();
        _diskRead?.Dispose();
        _diskWrite?.Dispose();
        _netIn?.Dispose();
        _netOut?.Dispose();
        foreach (var c in _cpuCores) c.Dispose();
        _cpuCores.Clear();
    }
}

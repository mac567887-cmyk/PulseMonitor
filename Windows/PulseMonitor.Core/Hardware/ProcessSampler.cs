using System.Diagnostics;
using PulseMonitor.Core.Models;

namespace PulseMonitor.Core.Hardware;

public sealed class ProcessSampler
{
    private readonly Dictionary<int, (TimeSpan cpu, DateTimeOffset at)> _prev = new();

    public IReadOnlyList<ProcessRow> SampleTop(int limit = 40)
    {
        var now = DateTimeOffset.UtcNow;
        var rows = new List<ProcessRow>();
        foreach (var p in Process.GetProcesses())
        {
            try
            {
                var cpuTime = p.TotalProcessorTime;
                var pid = p.Id;
                double cpuPct = 0;
                if (_prev.TryGetValue(pid, out var prev))
                {
                    var dCpu = (cpuTime - prev.cpu).TotalMilliseconds;
                    var dWall = (now - prev.at).TotalMilliseconds;
                    if (dWall > 0)
                        cpuPct = Math.Clamp(dCpu / dWall / Environment.ProcessorCount * 100.0, 0, 100);
                }
                _prev[pid] = (cpuTime, now);
                rows.Add(new ProcessRow
                {
                    Pid = pid,
                    Name = string.IsNullOrWhiteSpace(p.ProcessName) ? $"pid:{pid}" : p.ProcessName,
                    CpuPercent = cpuPct,
                    WorkingSetBytes = p.WorkingSet64
                });
            }
            catch
            {
                // access denied / exited
            }
            finally
            {
                p.Dispose();
            }
        }

        // Prune stale PIDs
        var live = rows.Select(r => r.Pid).ToHashSet();
        foreach (var key in _prev.Keys.Where(k => !live.Contains(k)).ToList())
            _prev.Remove(key);

        return rows.OrderByDescending(r => r.CpuPercent).Take(limit).ToList();
    }
}

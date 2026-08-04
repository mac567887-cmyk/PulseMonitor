using PulseMonitor.Core.Analytics;
using PulseMonitor.Core.Hardware;
using PulseMonitor.Core.Models;

namespace PulseMonitor.Core;

/// <summary>
/// Shared session used by the WinUI shell. Mirrors macOS AppContainer responsibilities.
/// </summary>
public sealed class AppSession : IDisposable
{
    private readonly MetricsCollector _metrics = new();
    private readonly ProcessSampler _processes = new();
    private readonly object _gate = new();
    private CancellationTokenSource? _cts;

    public MetricSnapshot? Latest { get; private set; }
    public IReadOnlyList<ProcessRow> Processes { get; private set; } = Array.Empty<ProcessRow>();
    public IReadOnlyList<EventFinding> Insights { get; private set; } = Array.Empty<EventFinding>();
    public double HealthScore { get; private set; } = 100;
    public event Action? Updated;

    public void Start(TimeSpan interval)
    {
        Stop();
        _cts = new CancellationTokenSource();
        var token = _cts.Token;
        _ = Task.Run(async () =>
        {
            while (!token.IsCancellationRequested)
            {
                try { Tick(); }
                catch { /* keep loop alive */ }
                try { await Task.Delay(interval, token); }
                catch (TaskCanceledException) { break; }
            }
        }, token);
    }

    public void Stop()
    {
        _cts?.Cancel();
        _cts?.Dispose();
        _cts = null;
    }

    public void Tick()
    {
        var snap = _metrics.Sample();
        var procs = _processes.SampleTop();
        var insights = InsightEngine.Analyze(snap, procs);
        var score = InsightEngine.HealthScore(snap, insights);
        lock (_gate)
        {
            Latest = snap;
            Processes = procs;
            Insights = insights;
            HealthScore = score;
        }
        Updated?.Invoke();
    }

    public DiagnosticReport ExportReport()
    {
        lock (_gate)
        {
            var m = Latest ?? _metrics.Sample();
            var p = Processes.Count > 0 ? Processes : _processes.SampleTop();
            return ReportExporter.Build(m, p);
        }
    }

    public void Dispose()
    {
        Stop();
        _metrics.Dispose();
    }
}

using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using PulseMonitor.Core.Analytics;
using PulseMonitor.Core.Hardware;
using PulseMonitor.Core.Sync;

namespace PulseMonitor.App;

public partial class MainWindow : Window
{
    private static readonly (string Tag, string Title)[] Modules =
    {
        ("dashboard", "Dashboard"),
        ("cpu", "CPU"),
        ("gpu", "GPU / DirectX"),
        ("memory", "Memory"),
        ("storage", "Storage"),
        ("devices", "Devices"),
        ("processes", "Processes"),
        ("services", "Services"),
        ("events", "Event Viewer"),
        ("bsod", "BSOD Analyzer"),
        ("drivers", "Driver Center"),
        ("gaming", "Gaming Hub"),
        ("anticheat", "Anti-Cheat"),
        ("updates", "Windows Update"),
        ("controls", "Control Center"),
        ("insights", "AI Insights"),
        ("reports", "Reports / Sync"),
        ("settings", "Settings"),
    };

    private string _tag = "dashboard";

    public MainWindow()
    {
        InitializeComponent();
        foreach (var m in Modules)
            NavList.Items.Add(new ListBoxItem { Content = m.Title, Tag = m.Tag });
        NavList.SelectedIndex = 0;
        App.Session.Updated += () => Dispatcher.Invoke(Render);
        Render();
    }

    private void NavList_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (NavList.SelectedItem is ListBoxItem item && item.Tag is string tag)
        {
            _tag = tag;
            Render();
        }
    }

    private void Render()
    {
        ContentHost.Children.Clear();
        var session = App.Session;
        var metrics = session.Latest;
        var title = Modules.First(m => m.Tag == _tag).Title;

        ContentHost.Children.Add(Ui.Title(title));
        ContentHost.Children.Add(Ui.Caption(CaptionFor(_tag)));
        ContentHost.Children.Add(Ui.Spacer());

        switch (_tag)
        {
            case "dashboard":
                ContentHost.Children.Add(Ui.MetricGrid(metrics, session.HealthScore));
                ContentHost.Children.Add(Ui.Spacer());
                ContentHost.Children.Add(Ui.Findings(session.Insights));
                break;
            case "cpu":
                ContentHost.Children.Add(Ui.P($"Brand: {CpuIdentity.Brand() ?? "—"}"));
                ContentHost.Children.Add(Ui.P($"Total: {metrics?.CpuPercent:0.0}% · Thermal: {metrics?.ThermalState ?? "—"} · Temp: {FmtTemp(metrics?.CpuTemperatureC)}"));
                ContentHost.Children.Add(Ui.CoreBars(metrics?.CpuPerCorePercent));
                ContentHost.Children.Add(Ui.Unavailable(metrics));
                break;
            case "gpu":
                var dx = DirectXInfo.Probe();
                ContentHost.Children.Add(Ui.P($"Primary: {metrics?.GpuName ?? "—"} · Util: {FmtPct(metrics?.GpuPercent)}"));
                ContentHost.Children.Add(Ui.P(dx.DirectXVersionHint ?? "DirectX"));
                foreach (var a in dx.Adapters)
                    ContentHost.Children.Add(Ui.P($"{a.Name} · driver {a.Driver ?? "—"}"));
                ContentHost.Children.Add(Ui.Caption(dx.HonestyNote));
                ContentHost.Children.Add(Ui.Unavailable(metrics));
                break;
            case "memory":
                ContentHost.Children.Add(Ui.P($"{metrics?.MemoryPercent:0}% used · {FmtBytes(metrics?.MemoryUsedBytes)} / {FmtBytes(metrics?.MemoryTotalBytes)}"));
                break;
            case "storage":
                foreach (var v in StorageAnalyzer.Volumes())
                    ContentHost.Children.Add(Ui.P($"{v.Name} {v.FileSystem} · free {FmtBytes(v.FreeBytes)} / {FmtBytes(v.TotalBytes)}{(v.BitLockerHint ? " · BitLocker on" : "")}"));
                foreach (var d in StorageAnalyzer.PhysicalDisks())
                    ContentHost.Children.Add(Ui.P($"{d.Model} · {d.InterfaceType} · {FmtBytes(d.SizeBytes)} — {d.SmartNote}"));
                break;
            case "devices":
                foreach (var d in DeviceCatalogue.Enumerate().Take(60))
                    ContentHost.Children.Add(Ui.P($"[{d.Category}] {d.Name} · {d.Status ?? "—"} · {d.Manufacturer ?? ""}"));
                break;
            case "processes":
                ContentHost.Children.Add(Ui.P("PID · CPU% · Working Set · Name"));
                foreach (var r in session.Processes.Take(35))
                    ContentHost.Children.Add(Ui.P($"{r.Pid,6}  {r.CpuPercent,5:0.0}%  {r.WorkingSetBytes / (1024 * 1024),6} MB  {r.Name}"));
                break;
            case "services":
                foreach (var s in ServiceInspector.ListServices(60).Where(x => x.Status == "Running").Take(30))
                    ContentHost.Children.Add(Ui.P($"{s.DisplayName} · {s.Status} · {s.StartType}"));
                foreach (var (name, cmd) in ServiceInspector.StartupCommands().Take(20))
                    ContentHost.Children.Add(Ui.P($"Startup: {name} → {cmd}"));
                break;
            case "events":
                ContentHost.Children.Add(Ui.Findings(EventLogAnalyzer.SummarizeRecent()));
                break;
            case "bsod":
                ContentHost.Children.Add(Ui.Findings(BsodAnalyzer.ScanMinidumps()));
                break;
            case "drivers":
                foreach (var d in DriverCenter.EnumerateKeyDrivers().Take(40))
                    ContentHost.Children.Add(Ui.P($"[{d.Category}] {d.DeviceName} · {d.DriverVersion ?? "—"} · {d.Manufacturer ?? ""}"));
                break;
            case "gaming":
                foreach (var l in GamingHub.DetectLaunchers())
                    ContentHost.Children.Add(Ui.P($"{(l.Detected ? "●" : "○")} {l.DisplayName}{(l.InstallPath is null ? "" : " — " + l.InstallPath)}"));
                foreach (var g in GamingHub.DiscoverSteamGamesRough().Take(40))
                    ContentHost.Children.Add(Ui.P($"Game: {g.Name} ({g.Launcher})"));
                break;
            case "anticheat":
                ContentHost.Children.Add(Ui.Caption("Warn before overlays — never interfere with protected games."));
                foreach (var h in AntiCheatDetector.Scan())
                    ContentHost.Children.Add(Ui.P($"{(h.Active ? "ACTIVE" : "idle")} · {h.Name} ({h.ProcessHint})"));
                break;
            case "updates":
                var u = WindowsUpdateProbe.Probe();
                ContentHost.Children.Add(Ui.P(u.Summary));
                foreach (var n in u.Notes) ContentHost.Children.Add(Ui.P("• " + n));
                break;
            case "controls":
                ContentHost.Children.Add(Ui.Caption("Fan, RGB, and overclock apply paths stay gated until vendor bridges exist."));
                foreach (var c in ControlCapabilities.Snapshot())
                    ContentHost.Children.Add(Ui.P($"{c.Id}: {c.Status} — {c.Reason}"));
                break;
            case "insights":
                ContentHost.Children.Add(Ui.Findings(session.Insights));
                break;
            case "reports":
                ContentHost.Children.Add(Ui.Button("Export diagnostic report (JSON 4.0)", () =>
                {
                    var report = session.ExportReport();
                    var path = Path.Combine(
                        Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments),
                        $"PulseMonitor-Report-{DateTime.Now:yyyyMMdd-HHmmss}.json");
                    ReportExporter.WriteJson(report, path);
                    MessageBox.Show($"Wrote {path}", "PulseMonitor");
                }));
                ContentHost.Children.Add(Ui.Spacer(8));
                ContentHost.Children.Add(Ui.Button("Export sync bundle", () =>
                {
                    var path = SyncStore.Export(new SyncBundle
                    {
                        Settings = new Dictionary<string, object?>
                        {
                            ["refreshIntervalSeconds"] = 2,
                            ["overlayEnabled"] = false,
                            ["notificationsEnabled"] = true,
                            ["activeProfile"] = "Balanced"
                        }
                    });
                    MessageBox.Show($"Sync bundle: {path}", "PulseMonitor");
                }));
                ContentHost.Children.Add(Ui.Caption("Reports use Shared/Schemas/report.schema.json — identical on macOS."));
                break;
            case "settings":
                ContentHost.Children.Add(Ui.P("PulseMonitor 4.0 Windows Edition"));
                ContentHost.Children.Add(Ui.P($"OS: {Environment.OSVersion}"));
                ContentHost.Children.Add(Ui.P($"Runtime: {RuntimeInformation.FrameworkDescription}"));
                ContentHost.Children.Add(Ui.Caption("Local-only. No telemetry. Same design language as the macOS app."));
                break;
        }
    }

    private static string CaptionFor(string tag) => tag switch
    {
        "dashboard" => "Live PDH / WMI / Win32 metrics with honest capability gating.",
        "controls" => "Never apply fan, RGB, or overclock changes automatically.",
        "bsod" => "Minidump catalogue + guidance — not a fake WinDbg.",
        _ => "Official Windows APIs first. Unavailable sensors show reasons, not zeros."
    };

    private static string FmtPct(double? v) => v is null ? "—" : $"{v:0.0}%";
    private static string FmtTemp(double? v) => v is null ? "—" : $"{v:0.0}°C";
    private static string FmtBytes(ulong? v)
    {
        if (v is null or 0) return "—";
        double d = v.Value;
        string[] u = { "B", "KB", "MB", "GB", "TB" };
        var i = 0;
        while (d >= 1024 && i < u.Length - 1) { d /= 1024; i++; }
        return $"{d:0.0} {u[i]}";
    }
}

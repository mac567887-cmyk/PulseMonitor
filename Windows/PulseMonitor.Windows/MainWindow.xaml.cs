using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using PulseMonitor.Core;
using PulseMonitor.Core.Analytics;
using PulseMonitor.Core.Hardware;
using PulseMonitor.Core.Sync;
using PulseMonitor.Windows.Pages;
using System.Runtime.InteropServices;
using Windows.Graphics;

namespace PulseMonitor.Windows;

public sealed partial class MainWindow : Window
{
    private string _tag = "dashboard";

    public MainWindow()
    {
        InitializeComponent();
        Title = "PulseMonitor 4 · Windows";
        TryResize(1280, 840);
        App.Session.Updated += OnSessionUpdated;
        Nav.SelectedItem = Nav.MenuItems[0];
        Render();
    }

    private void TryResize(int w, int h)
    {
        try
        {
            var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(this);
            var id = Microsoft.UI.Win32Interop.GetWindowIdFromWindow(hwnd);
            var appWindow = Microsoft.UI.Windowing.AppWindow.GetFromWindowId(id);
            appWindow?.Resize(new SizeInt32(w, h));
        }
        catch { }
    }

    private void OnSessionUpdated()
    {
        DispatcherQueue.TryEnqueue(Render);
    }

    private void Nav_SelectionChanged(NavigationView sender, NavigationViewSelectionChangedEventArgs args)
    {
        if (args.IsSettingsSelected)
        {
            _tag = "settings";
            Render();
            return;
        }
        if (args.SelectedItem is NavigationViewItem item && item.Tag is string tag)
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

        ContentHost.Children.Add(UiFactory.Title(ModuleTitle(_tag)));
        ContentHost.Children.Add(UiFactory.Caption(ModuleCaption(_tag)));

        switch (_tag)
        {
            case "dashboard":
                ContentHost.Children.Add(UiFactory.MetricGrid(metrics, session.HealthScore));
                ContentHost.Children.Add(UiFactory.FindingsList(session.Insights));
                break;
            case "cpu":
                ContentHost.Children.Add(UiFactory.Paragraph($"Brand: {CpuIdentity.Brand() ?? "—"}"));
                ContentHost.Children.Add(UiFactory.Paragraph($"Total: {metrics?.CpuPercent:0.0}% · Thermal: {metrics?.ThermalState ?? "—"} · Temp: {FmtTemp(metrics?.CpuTemperatureC)}"));
                ContentHost.Children.Add(UiFactory.CoreBars(metrics?.CpuPerCorePercent));
                ContentHost.Children.Add(UiFactory.Unavailable(metrics));
                break;
            case "gpu":
                var dx = DirectXInfo.Probe();
                ContentHost.Children.Add(UiFactory.Paragraph($"Primary: {metrics?.GpuName ?? "—"} · Util: {FmtPct(metrics?.GpuPercent)}"));
                ContentHost.Children.Add(UiFactory.Paragraph(dx.DirectXVersionHint ?? "DirectX"));
                foreach (var a in dx.Adapters)
                    ContentHost.Children.Add(UiFactory.Paragraph($"{a.Name} · driver {a.Driver ?? "—"}"));
                ContentHost.Children.Add(UiFactory.Caption(dx.HonestyNote));
                ContentHost.Children.Add(UiFactory.Unavailable(metrics));
                break;
            case "memory":
                ContentHost.Children.Add(UiFactory.Paragraph($"{metrics?.MemoryPercent:0}% used · {FmtBytes(metrics?.MemoryUsedBytes)} / {FmtBytes(metrics?.MemoryTotalBytes)}"));
                break;
            case "storage":
                foreach (var v in StorageAnalyzer.Volumes())
                    ContentHost.Children.Add(UiFactory.Paragraph($"{v.Name} {v.FileSystem} · free {FmtBytes(v.FreeBytes)} / {FmtBytes(v.TotalBytes)}{(v.BitLockerHint ? " · BitLocker on" : "")}"));
                foreach (var d in StorageAnalyzer.PhysicalDisks())
                    ContentHost.Children.Add(UiFactory.Paragraph($"{d.Model} · {d.InterfaceType} · {FmtBytes(d.SizeBytes)} — {d.SmartNote}"));
                break;
            case "devices":
                ContentHost.Children.Add(UiFactory.Caption("USB, Bluetooth, monitors, audio, network — from WMI / PnP."));
                foreach (var d in DeviceCatalogue.Enumerate().Take(60))
                    ContentHost.Children.Add(UiFactory.Paragraph($"[{d.Category}] {d.Name} · {d.Status ?? "—"} · {d.Manufacturer ?? ""}"));
                break;
            case "processes":
                ContentHost.Children.Add(UiFactory.ProcessTable(session.Processes));
                break;
            case "services":
                ContentHost.Children.Add(UiFactory.Caption("Running services & startup commands (read-only)."));
                foreach (var s in ServiceInspector.ListServices(60).Where(x => x.Status == "Running").Take(30))
                    ContentHost.Children.Add(UiFactory.Paragraph($"{s.DisplayName} · {s.Status} · {s.StartType}"));
                foreach (var (name, cmd) in ServiceInspector.StartupCommands().Take(20))
                    ContentHost.Children.Add(UiFactory.Paragraph($"Startup: {name} → {cmd}"));
                break;
            case "events":
                ContentHost.Children.Add(UiFactory.FindingsList(EventLogAnalyzer.SummarizeRecent()));
                break;
            case "bsod":
                ContentHost.Children.Add(UiFactory.FindingsList(BsodAnalyzer.ScanMinidumps()));
                break;
            case "drivers":
                foreach (var d in DriverCenter.EnumerateKeyDrivers().Take(40))
                    ContentHost.Children.Add(UiFactory.Paragraph($"[{d.Category}] {d.DeviceName} · {d.DriverVersion ?? "—"} · {d.Manufacturer ?? ""}"));
                break;
            case "gaming":
                foreach (var l in GamingHub.DetectLaunchers())
                    ContentHost.Children.Add(UiFactory.Paragraph($"{(l.Detected ? "●" : "○")} {l.DisplayName}{(l.InstallPath is null ? "" : " — " + l.InstallPath)}"));
                foreach (var g in GamingHub.DiscoverSteamGamesRough().Take(40))
                    ContentHost.Children.Add(UiFactory.Paragraph($"Game: {g.Name} ({g.Launcher})"));
                break;
            case "anticheat":
                ContentHost.Children.Add(UiFactory.Caption("Warn before overlays — never interfere with protected games."));
                foreach (var h in AntiCheatDetector.Scan())
                    ContentHost.Children.Add(UiFactory.Paragraph($"{(h.Active ? "ACTIVE" : "idle")} · {h.Name} ({h.ProcessHint})"));
                break;
            case "updates":
                var u = WindowsUpdateProbe.Probe();
                ContentHost.Children.Add(UiFactory.Paragraph(u.Summary));
                foreach (var n in u.Notes) ContentHost.Children.Add(UiFactory.Paragraph("• " + n));
                break;
            case "controls":
                ContentHost.Children.Add(UiFactory.Caption("Fan, RGB, and overclock apply paths stay gated until vendor bridges exist."));
                foreach (var c in ControlCapabilities.Snapshot())
                    ContentHost.Children.Add(UiFactory.Paragraph($"{c.Id}: {c.Status} — {c.Reason}"));
                break;
            case "insights":
                ContentHost.Children.Add(UiFactory.FindingsList(session.Insights));
                break;
            case "reports":
                ContentHost.Children.Add(UiFactory.Button("Export diagnostic report (JSON 4.0)", (_, _) =>
                {
                    var report = session.ExportReport();
                    var path = Path.Combine(
                        Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments),
                        $"PulseMonitor-Report-{DateTime.Now:yyyyMMdd-HHmmss}.json");
                    ReportExporter.WriteJson(report, path);
                    ContentHost.Children.Add(UiFactory.Paragraph($"Wrote {path}"));
                }));
                ContentHost.Children.Add(UiFactory.Button("Export sync bundle", (_, _) =>
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
                    ContentHost.Children.Add(UiFactory.Paragraph($"Sync bundle: {path}"));
                }));
                ContentHost.Children.Add(UiFactory.Caption("Reports use Shared/Schemas/report.schema.json — identical on macOS."));
                break;
            case "settings":
                ContentHost.Children.Add(UiFactory.Paragraph("PulseMonitor 4.0 Windows Edition"));
                ContentHost.Children.Add(UiFactory.Paragraph($"OS: {Environment.OSVersion}"));
                ContentHost.Children.Add(UiFactory.Paragraph($"Runtime: {RuntimeInformation.FrameworkDescription}"));
                ContentHost.Children.Add(UiFactory.Caption("Local-only. No telemetry. Same design language as the macOS app."));
                break;
        }
    }

    private static string ModuleTitle(string tag) => tag switch
    {
        "dashboard" => "Dashboard",
        "cpu" => "CPU",
        "gpu" => "GPU / DirectX Analyzer",
        "memory" => "Memory",
        "storage" => "Storage Analysis",
        "devices" => "PCIe / USB / Bluetooth / Audio / Monitors",
        "processes" => "Process Explorer",
        "services" => "Windows Services",
        "events" => "Event Viewer Analyzer",
        "bsod" => "BSOD Analyzer",
        "drivers" => "Driver Center",
        "gaming" => "Gaming Hub",
        "anticheat" => "Anti-Cheat Detection",
        "updates" => "Windows Update Analysis",
        "controls" => "Control Center (Fans / RGB / OC)",
        "insights" => "Windows AI Insights",
        "reports" => "Reports & Sync",
        "settings" => "Settings",
        _ => "PulseMonitor"
    };

    private static string ModuleCaption(string tag) => tag switch
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

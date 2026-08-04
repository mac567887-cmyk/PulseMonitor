using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using PulseMonitor.Core.Models;
using Windows.UI;

namespace PulseMonitor.Windows.Pages;

internal static class UiFactory
{
    public static TextBlock Title(string text) => new()
    {
        Text = text,
        FontSize = 28,
        FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
        Foreground = Brush(255, 240, 244, 250)
    };

    public static TextBlock Caption(string text) => new()
    {
        Text = text,
        FontSize = 13,
        Opacity = 0.75,
        TextWrapping = TextWrapping.Wrap,
        Foreground = Brush(255, 180, 190, 205)
    };

    public static TextBlock Paragraph(string text) => new()
    {
        Text = text,
        FontSize = 14,
        TextWrapping = TextWrapping.Wrap,
        Foreground = Brush(255, 220, 228, 238)
    };

    public static Button Button(string label, RoutedEventHandler handler)
    {
        var b = new Button { Content = label, Padding = new Thickness(14, 8, 14, 8) };
        b.Click += handler;
        return b;
    }

    public static Grid MetricGrid(MetricSnapshot? m, double health)
    {
        var grid = new Grid { ColumnSpacing = 12, RowSpacing = 12 };
        for (var i = 0; i < 3; i++)
        {
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        }

        void Add(int r, int c, string title, string value)
        {
            var border = new Border
            {
                Background = Brush(255, 20, 26, 34),
                CornerRadius = new CornerRadius(12),
                Padding = new Thickness(16),
                Child = new StackPanel
                {
                    Spacing = 6,
                    Children =
                    {
                        new TextBlock { Text = title, Opacity = 0.7, FontSize = 12, Foreground = Brush(255, 180, 190, 205) },
                        new TextBlock { Text = value, FontSize = 22, FontWeight = Microsoft.UI.Text.FontWeights.SemiBold, Foreground = Brush(255, 61, 156, 240) }
                    }
                }
            };
            Grid.SetRow(border, r);
            Grid.SetColumn(border, c);
            grid.Children.Add(border);
        }

        Add(0, 0, "Health", $"{health:0}");
        Add(0, 1, "CPU", m is null ? "—" : $"{m.CpuPercent:0.0}%");
        Add(0, 2, "GPU", m?.GpuPercent is double g ? $"{g:0.0}%" : "—");
        Add(1, 0, "Memory", m is null ? "—" : $"{m.MemoryPercent:0}%");
        Add(1, 1, "Disk R/W", m is null ? "—" : $"{FmtRate(m.DiskReadBps)} / {FmtRate(m.DiskWriteBps)}");
        Add(1, 2, "Network", m is null ? "—" : $"{FmtRate(m.NetworkInBps)} ↓  {FmtRate(m.NetworkOutBps)} ↑");
        return grid;
    }

    public static StackPanel FindingsList(IReadOnlyList<EventFinding> findings)
    {
        var panel = new StackPanel { Spacing = 10 };
        if (findings.Count == 0)
        {
            panel.Children.Add(Paragraph("No findings right now."));
            return panel;
        }
        foreach (var f in findings.Take(20))
        {
            panel.Children.Add(new Border
            {
                Background = Brush(255, 20, 26, 34),
                CornerRadius = new CornerRadius(10),
                Padding = new Thickness(14),
                Child = new StackPanel
                {
                    Spacing = 4,
                    Children =
                    {
                        new TextBlock { Text = $"[{f.Severity}] {f.Title}", FontWeight = Microsoft.UI.Text.FontWeights.SemiBold, Foreground = Brush(255, 240, 244, 250) },
                        new TextBlock { Text = f.Summary, TextWrapping = TextWrapping.Wrap, Opacity = 0.85, Foreground = Brush(255, 200, 210, 220) }
                    }
                }
            });
        }
        return panel;
    }

    public static StackPanel ProcessTable(IReadOnlyList<ProcessRow> rows)
    {
        var panel = new StackPanel { Spacing = 4 };
        panel.Children.Add(Paragraph("PID · CPU% · Working Set · Name"));
        foreach (var r in rows.Take(35))
            panel.Children.Add(Paragraph($"{r.Pid,6}  {r.CpuPercent,5:0.0}%  {r.WorkingSetBytes / (1024 * 1024),6} MB  {r.Name}"));
        return panel;
    }

    public static StackPanel CoreBars(IReadOnlyList<double>? cores)
    {
        var panel = new StackPanel { Spacing = 6 };
        if (cores is null || cores.Count == 0)
        {
            panel.Children.Add(Paragraph("Per-core counters unavailable."));
            return panel;
        }
        for (var i = 0; i < cores.Count; i++)
        {
            panel.Children.Add(new StackPanel
            {
                Orientation = Orientation.Horizontal,
                Spacing = 8,
                Children =
                {
                    new TextBlock { Text = $"C{i}", Width = 36, Foreground = Brush(255, 180, 190, 205) },
                    new ProgressBar { Value = cores[i], Maximum = 100, Width = 280, Height = 8 },
                    new TextBlock { Text = $"{cores[i]:0}%", Foreground = Brush(255, 220, 228, 238) }
                }
            });
        }
        return panel;
    }

    public static StackPanel Unavailable(MetricSnapshot? m)
    {
        var panel = new StackPanel { Spacing = 4 };
        if (m is null || m.Unavailable.Count == 0) return panel;
        panel.Children.Add(Caption("Unavailable (honest gating):"));
        foreach (var kv in m.Unavailable.Take(8))
            panel.Children.Add(Paragraph($"• {kv.Key}: {kv.Value}"));
        return panel;
    }

    private static SolidColorBrush Brush(byte a, byte r, byte g, byte b)
        => new(Color.FromArgb(a, r, g, b));

    private static string FmtRate(double bps)
    {
        double d = bps;
        string[] u = { "B/s", "KB/s", "MB/s", "GB/s" };
        var i = 0;
        while (d >= 1024 && i < u.Length - 1) { d /= 1024; i++; }
        return $"{d:0.0} {u[i]}";
    }
}

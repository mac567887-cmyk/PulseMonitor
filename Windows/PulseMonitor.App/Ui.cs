using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using PulseMonitor.Core.Models;

namespace PulseMonitor.App;

internal static class Ui
{
    private static readonly Brush Text = Brush("#F0F4FA");
    private static readonly Brush Muted = Brush("#B4BED1");
    private static readonly Brush Accent = Brush("#3D9CF0");
    private static readonly Brush Panel = Brush("#141A22");

    public static TextBlock Title(string t) => new()
    {
        Text = t, FontSize = 28, FontWeight = FontWeights.SemiBold, Foreground = Text, Margin = new Thickness(0, 0, 0, 4)
    };

    public static TextBlock Caption(string t) => new()
    {
        Text = t, FontSize = 13, Foreground = Muted, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 0, 0, 8)
    };

    public static TextBlock P(string t) => new()
    {
        Text = t, FontSize = 14, Foreground = Text, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 2, 0, 2)
    };

    public static FrameworkElement Spacer(double h = 16) => new Border { Height = h };

    public static Button Button(string label, Action onClick)
    {
        var b = new Button
        {
            Content = label,
            Padding = new Thickness(14, 8, 14, 8),
            Margin = new Thickness(0, 4, 0, 4),
            HorizontalAlignment = HorizontalAlignment.Left
        };
        b.Click += (_, _) => onClick();
        return b;
    }

    public static Grid MetricGrid(MetricSnapshot? m, double health)
    {
        var grid = new Grid { Margin = new Thickness(0, 8, 0, 8) };
        for (var i = 0; i < 3; i++)
        {
            grid.ColumnDefinitions.Add(new ColumnDefinition());
            grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        }

        void Add(int r, int c, string title, string value)
        {
            var border = new Border
            {
                Background = Panel,
                CornerRadius = new CornerRadius(12),
                Padding = new Thickness(16),
                Margin = new Thickness(0, 0, 12, 12),
                Child = new StackPanel
                {
                    Children =
                    {
                        new TextBlock { Text = title, Foreground = Muted, FontSize = 12 },
                        new TextBlock { Text = value, Foreground = Accent, FontSize = 22, FontWeight = FontWeights.SemiBold, Margin = new Thickness(0, 6, 0, 0) }
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

    public static StackPanel Findings(IReadOnlyList<EventFinding> findings)
    {
        var panel = new StackPanel();
        if (findings.Count == 0)
        {
            panel.Children.Add(P("No findings right now."));
            return panel;
        }
        foreach (var f in findings.Take(20))
        {
            panel.Children.Add(new Border
            {
                Background = Panel,
                CornerRadius = new CornerRadius(10),
                Padding = new Thickness(14),
                Margin = new Thickness(0, 0, 0, 10),
                Child = new StackPanel
                {
                    Children =
                    {
                        new TextBlock { Text = $"[{f.Severity}] {f.Title}", FontWeight = FontWeights.SemiBold, Foreground = Text },
                        new TextBlock { Text = f.Summary, TextWrapping = TextWrapping.Wrap, Foreground = Muted, Margin = new Thickness(0, 4, 0, 0) }
                    }
                }
            });
        }
        return panel;
    }

    public static StackPanel CoreBars(IReadOnlyList<double>? cores)
    {
        var panel = new StackPanel { Margin = new Thickness(0, 8, 0, 8) };
        if (cores is null || cores.Count == 0)
        {
            panel.Children.Add(P("Per-core counters unavailable."));
            return panel;
        }
        for (var i = 0; i < cores.Count; i++)
        {
            var row = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 3, 0, 3) };
            row.Children.Add(new TextBlock { Text = $"C{i}", Width = 36, Foreground = Muted, VerticalAlignment = VerticalAlignment.Center });
            row.Children.Add(new ProgressBar { Value = cores[i], Maximum = 100, Width = 280, Height = 10 });
            row.Children.Add(new TextBlock { Text = $" {cores[i]:0}%", Foreground = Text, VerticalAlignment = VerticalAlignment.Center });
            panel.Children.Add(row);
        }
        return panel;
    }

    public static StackPanel Unavailable(MetricSnapshot? m)
    {
        var panel = new StackPanel { Margin = new Thickness(0, 12, 0, 0) };
        if (m is null || m.Unavailable.Count == 0) return panel;
        panel.Children.Add(Caption("Unavailable (honest gating):"));
        foreach (var kv in m.Unavailable.Take(8))
            panel.Children.Add(P($"• {kv.Key}: {kv.Value}"));
        return panel;
    }

    private static SolidColorBrush Brush(string hex) =>
        (SolidColorBrush)new BrushConverter().ConvertFromString(hex)!;

    private static string FmtRate(double bps)
    {
        double d = bps;
        string[] u = { "B/s", "KB/s", "MB/s", "GB/s" };
        var i = 0;
        while (d >= 1024 && i < u.Length - 1) { d /= 1024; i++; }
        return $"{d:0.0} {u[i]}";
    }
}

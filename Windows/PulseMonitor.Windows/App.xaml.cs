using Microsoft.UI.Xaml;
using PulseMonitor.Core;

namespace PulseMonitor.Windows;

public partial class App : Application
{
    private Window? _window;
    public static AppSession Session { get; } = new();

    public App()
    {
        InitializeComponent();
        UnhandledException += (_, e) =>
        {
            e.Handled = true;
        };
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        Session.Start(TimeSpan.FromSeconds(2));
        _window = new MainWindow();
        _window.Activate();
    }
}

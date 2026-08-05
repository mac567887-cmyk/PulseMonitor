using System.Windows;
using PulseMonitor.Core;

namespace PulseMonitor.App;

public partial class App : Application
{
    public static AppSession Session { get; } = new();

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        Session.Start(TimeSpan.FromSeconds(2));
    }

    protected override void OnExit(ExitEventArgs e)
    {
        Session.Dispose();
        base.OnExit(e);
    }
}

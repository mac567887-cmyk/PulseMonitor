using System.Diagnostics;

namespace PulseMonitor.Core.Hardware;

public sealed class AntiCheatHit
{
    public required string Name { get; init; }
    public required string ProcessHint { get; init; }
    public bool Active { get; init; }
}

public static class AntiCheatDetector
{
    private static readonly (string Name, string[] Processes)[] Known =
    {
        ("Easy Anti-Cheat", new[] { "EasyAntiCheat", "EasyAntiCheat_EOS" }),
        ("BattlEye", new[] { "BEService", "BattlEye" }),
        ("Vanguard (Riot)", new[] { "vgtray", "vgc" }),
        ("FACEIT", new[] { "faceit", "faceitclient" }),
        ("PunkBuster", new[] { "PnkBstrA", "PnkBstrB" }),
        ("nProtect GameGuard", new[] { "GameGuard", "GameMon" }),
        ("Ricochet", new[] { "cod", "bootstrapper" }), // soft hint only
    };

    public static IReadOnlyList<AntiCheatHit> Scan()
    {
        HashSet<string> running;
        try
        {
            running = Process.GetProcesses()
                .Select(p =>
                {
                    try { return p.ProcessName; }
                    finally { p.Dispose(); }
                })
                .Where(n => !string.IsNullOrWhiteSpace(n))
                .ToHashSet(StringComparer.OrdinalIgnoreCase);
        }
        catch
        {
            running = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        }

        return Known.Select(k => new AntiCheatHit
        {
            Name = k.Name,
            ProcessHint = string.Join(", ", k.Processes),
            Active = k.Processes.Any(p => running.Contains(p))
        }).ToList();
    }

    public static bool ShouldWarnOverlay()
        => Scan().Any(h => h.Active && h.Name != "Ricochet");
}

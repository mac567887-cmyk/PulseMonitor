namespace PulseMonitor.Core.Hardware;

public sealed class GameLauncherInfo
{
    public required string Id { get; init; }
    public required string DisplayName { get; init; }
    public bool Detected { get; init; }
    public string? InstallPath { get; init; }
}

public sealed class DetectedGame
{
    public required string Name { get; init; }
    public required string Launcher { get; init; }
    public string? Path { get; init; }
}

public static class GamingHub
{
    private static readonly (string Id, string Name, string[] Markers)[] Launchers =
    {
        ("steam", "Steam", new[] { @"Program Files (x86)\Steam\steam.exe", @"Program Files\Steam\steam.exe" }),
        ("epic", "Epic Games", new[] { @"Program Files (x86)\Epic Games\Launcher\Portal\Binaries\Win32\EpicGamesLauncher.exe", @"Program Files\Epic Games\Launcher\Portal\Binaries\Win64\EpicGamesLauncher.exe" }),
        ("battlenet", "Battle.net", new[] { @"Program Files (x86)\Battle.net\Battle.net.exe" }),
        ("ea", "EA App", new[] { @"Program Files\Electronic Arts\EA Desktop\EA Desktop\EADesktop.exe", @"Program Files\EA Games\EA Desktop\EA Desktop\EADesktop.exe" }),
        ("ubisoft", "Ubisoft Connect", new[] { @"Program Files (x86)\Ubisoft\Ubisoft Game Launcher\UbisoftConnect.exe" }),
        ("xbox", "Xbox App", new[] { @"WindowsApps" }), // presence via package / process heuristic
        ("gog", "GOG Galaxy", new[] { @"Program Files (x86)\GOG Galaxy\GalaxyClient.exe" }),
        ("heroic", "Heroic", new[] { @"Users" }), // path varies; also check LocalAppData
        ("minecraft", "Minecraft Launcher", new[] { @"Program Files (x86)\Minecraft Launcher\MinecraftLauncher.exe" }),
    };

    public static IReadOnlyList<GameLauncherInfo> DetectLaunchers()
    {
        var drive = Path.GetPathRoot(Environment.SystemDirectory) ?? @"C:\";
        var list = new List<GameLauncherInfo>();

        foreach (var (id, name, markers) in Launchers)
        {
            string? found = null;
            if (id == "xbox")
            {
                found = Directory.Exists(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Packages"))
                    ? "Xbox / Microsoft Store packages present"
                    : null;
            }
            else if (id == "heroic")
            {
                var heroic = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs", "heroic", "Heroic.exe");
                if (File.Exists(heroic)) found = heroic;
            }
            else
            {
                foreach (var m in markers)
                {
                    var full = Path.IsPathRooted(m) ? m : Path.Combine(drive, m);
                    if (File.Exists(full) || Directory.Exists(full))
                    {
                        found = full;
                        break;
                    }
                }
            }

            list.Add(new GameLauncherInfo
            {
                Id = id,
                DisplayName = name,
                Detected = found is not null,
                InstallPath = found
            });
        }

        return list;
    }

    public static IReadOnlyList<DetectedGame> DiscoverSteamGamesRough()
    {
        // Lightweight libraryfolders.vdf parse — best-effort, no invented titles.
        var games = new List<DetectedGame>();
        var candidates = new[]
        {
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), "Steam", "steamapps", "libraryfolders.vdf"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "Steam", "steamapps", "libraryfolders.vdf"),
        };

        foreach (var libFile in candidates.Where(File.Exists))
        {
            try
            {
                var text = File.ReadAllText(libFile);
                foreach (var line in text.Split('\n'))
                {
                    var t = line.Trim();
                    if (!t.Contains("path", StringComparison.OrdinalIgnoreCase)) continue;
                    var parts = t.Split('"', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
                    if (parts.Length < 2) continue;
                    var path = parts.Last().Replace(@"\\", @"\");
                    var common = Path.Combine(path, "steamapps", "common");
                    if (!Directory.Exists(common)) continue;
                    foreach (var dir in Directory.GetDirectories(common).Take(80))
                    {
                        games.Add(new DetectedGame
                        {
                            Name = Path.GetFileName(dir),
                            Launcher = "Steam",
                            Path = dir
                        });
                    }
                }
            }
            catch { }
        }

        return games
            .GroupBy(g => g.Name, StringComparer.OrdinalIgnoreCase)
            .Select(g => g.First())
            .OrderBy(g => g.Name)
            .ToList();
    }
}

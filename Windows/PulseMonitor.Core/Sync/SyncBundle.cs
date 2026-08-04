using System.Text.Json;
using System.Text.Json.Serialization;

namespace PulseMonitor.Core.Sync;

public sealed class SyncBundle
{
    public string SchemaVersion { get; set; } = "4.0.0";
    public DateTimeOffset ExportedAt { get; set; } = DateTimeOffset.UtcNow;
    public Dictionary<string, object?> Settings { get; set; } = new();
    public string Theme { get; set; } = "pulse-dark";
    public List<object> Workspaces { get; set; } = new();
    public List<object> AutomationRules { get; set; } = new();
    public Dictionary<string, object?>? MenuBarStudio { get; set; }
    public List<object> WidgetBoard { get; set; } = new();
}

public static class SyncStore
{
    private static readonly JsonSerializerOptions Options = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull
    };

    public static string DefaultDirectory()
    {
        var dir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "PulseMonitor", "Sync");
        Directory.CreateDirectory(dir);
        return dir;
    }

    public static string Export(SyncBundle bundle, string? path = null)
    {
        path ??= Path.Combine(DefaultDirectory(), $"pulsemonitor-sync-{DateTime.UtcNow:yyyyMMdd-HHmmss}.json");
        File.WriteAllText(path, JsonSerializer.Serialize(bundle, Options));
        return path;
    }

    public static SyncBundle? Import(string path)
    {
        if (!File.Exists(path)) return null;
        return JsonSerializer.Deserialize<SyncBundle>(File.ReadAllText(path), Options);
    }
}

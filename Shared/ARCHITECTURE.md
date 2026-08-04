# PulseMonitor Cross-Platform Architecture (v4)

```
┌─────────────────────────────────────────────────────────────┐
│                     UI Layer                                │
│  macOS: SwiftUI          Windows: WinUI 3 / Windows App SDK │
└───────────────────────────┬─────────────────────────────────┘
                            │ view-models / DTOs
┌───────────────────────────▼─────────────────────────────────┐
│                     Core Engine (shared contracts)          │
│  Analytics · Health Score · Copilot rules · Reports · Sync  │
└───────────────┬─────────────────────────────┬───────────────┘
                │                             │
┌───────────────▼──────────────┐ ┌────────────▼────────────────┐
│  Hardware Abstraction (HAL)  │ │  Sensor Layer               │
│  macOS: IOKit/Mach/sysctl    │ │  Platform counters          │
│  Windows: WMI/PDH/DXGI/Win32 │ │  Optional vendor SDKs       │
└──────────────────────────────┘ └─────────────────────────────┘
```

## Repository layout

| Path | Role |
|------|------|
| `PulseMonitor/` | macOS SwiftUI app + SPM target |
| `Windows/PulseMonitor.Windows/` | WinUI 3 shell |
| `Windows/PulseMonitor.Core/` | .NET hardware/analytics engine (no UI) |
| `Shared/Schemas/` | JSON contracts for reports, snapshots, plugins, sync |
| `Shared/Capabilities/` | Capability gating tables (what each OS may expose) |

## Design rules

1. **Never invent sensors.** If WMI/PDH/IOKit does not publish a value, the UI shows `—` and a reason.
2. **Never apply destructive or overclock changes automatically.** Confirmation required; unsupported hardware disables controls.
3. **Same report schema** on both platforms (`Shared/Schemas/report.schema.json`).
4. **Plugins** declare capabilities in `plugin.manifest.schema.json`; native code is platform-specific.
5. **RGB / fan write / anti-cheat** are capability-gated. Missing vendor SDKs → catalogue + “unsupported”, not fake sliders.

## Sync

Profiles, themes, automation rules, and widget layouts serialize to JSON under the user data directory and can be copied between machines. Binary plugins are per-OS.

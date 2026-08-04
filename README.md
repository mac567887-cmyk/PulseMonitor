# PulseMonitor

![PulseMonitor](docs/app-icon.png)

Cross-platform hardware monitoring and control centre that explains **why** a
machine is slow — without inventing sensors.

![macOS](https://img.shields.io/badge/macOS-14%2B%20Sonoma-blue)
![Windows](https://img.shields.io/badge/Windows-10%20%2F%2011-0078D4)
![Privacy](https://img.shields.io/badge/Telemetry-None-success)

## Version 4.0 — Windows Edition

PulseMonitor is now a true cross-platform suite:

| OS | UI | Hardware layer |
|----|----|----------------|
| **macOS 14+** | SwiftUI | IOKit / Mach / sysctl / Metal / SMC |
| **Windows 10/11** | WinUI 3 / Windows App SDK | PDH / WMI / Win32 / Event Log / DXGI hints |

Shared contracts live in [`Shared/`](Shared/ARCHITECTURE.md): report schema **4.0.0**,
sync profiles, and capability tables. Reports and sync bundles are interchangeable
across platforms; native plugins remain per-OS.

### Windows modules

| Module | Source of truth |
|--------|-----------------|
| CPU / Memory / Disk / Network | Performance Counters (PDH) + `GlobalMemoryStatusEx` |
| GPU catalogue | `Win32_VideoController` + GPU Engine counters when present |
| DirectX Analyzer | Driver/adapter inventory; frame times require a capture bridge |
| Processes / Services / Startup | `Process` + `ServiceController` + `Win32_StartupCommand` |
| Event Viewer Analyzer | Windows Event Log API → plain-English findings |
| BSOD Analyzer | Minidump catalogue + WinDbg guidance (no invented faulting drivers) |
| Driver Center | `Win32_PnPSignedDriver` filtered to GPU/chipset/net/audio/monitor |
| Gaming Hub | Steam / Epic / Battle.net / EA / Ubisoft / Xbox / GOG / Heroic / Minecraft detection |
| Anti-Cheat | Process heuristics; warns before overlays; never injects |
| Storage | NTFS/ReFS/FAT/exFAT volumes, BitLocker hint, physical disk WMI |
| Windows Update | Service state + guided WUApi path (no silent policy changes) |
| Control Center | Fan / RGB / OC **gated** until optional vendor bridges exist |
| AI Insights | Discord HA, ShadowPlay, Search Indexer, Windows Update load |
| Reports / Sync | JSON schema shared with macOS |

### What Windows will not invent

| Feature | Status |
|---------|--------|
| GPU temperature / power / RT / tensor % | Unavailable without vendor SDK (NVAPI/ADL/IGCL) |
| Fan curve write | Disabled until `bridges/FanBridge.dll` is present |
| RGB write (Aura, iCUE, Chroma, …) | Catalogue host apps only unless an SDK bridge is installed |
| Overclock apply | Never automatic; confirmation + vendor API required |
| PSU telemetry | Not exposed by Windows APIs |
| Full minidump stack analysis | Delegates to WinDbg / optional dump bridge |

See [`Windows/README.md`](Windows/README.md) for Visual Studio build steps.

## Version 3.0 — Professional Edition (macOS)

Digital twin, multi-category health scoring, AI copilot, game lab, hardware labs,
snapshots/diff, workspaces, menu-bar studio, and optional token-gated local web
dashboard — still without inventing sensors.

## Version 2.0 — Tahoe Update (macOS)

Control centre, capability-gated panels, benchmarks, automation, overlay, widgets,
plugins, App Intents, and themes.

## What this app will not do

PulseMonitor never shows a control it cannot honour or a number it cannot
measure. Every gated feature states its reason in the UI.

| Feature | Status | Reason |
|---------|--------|--------|
| Manual fan control (Apple Silicon) | Disabled | OS blocks it; no privileged SMC helper installed |
| Frame rate / FPS estimates | Not offered | Requires private APIs or Metal HUD / DXGI capture |
| Neural Engine load | Unavailable | No public utilization API |
| Bluetooth codec quality | Not offered | Not published by CoreBluetooth |
| Third-party native plugins | Catalogued | Unsigned Mach-O / DLL plugin code is refused |

## Architecture

```
UI Layer          SwiftUI (macOS) · WinUI 3 (Windows)
Core Engine       Analytics · Health · Reports · Sync contracts
Hardware HAL      Platform-specific collectors
Sensor Layer      PDH/WMI/IOKit/… with honest nulls
Plugin API        Manifests in Shared/Schemas · native code per OS
```

| Path | Role |
|------|------|
| `PulseMonitor/` | macOS SwiftUI app |
| `Windows/PulseMonitor.Core/` | .NET hardware + analytics engine |
| `Windows/PulseMonitor.Windows/` | WinUI 3 shell |
| `Shared/` | JSON schemas + capability tables |

## Requirements

**macOS:** Sonoma 14+, Swift 6 (Xcode 16+ or CLT), Intel or Apple Silicon  
**Windows:** Windows 10/11, Visual Studio 2022, .NET 8, Windows App SDK

## Build & Run

### macOS

```bash
./Scripts/bundle.sh
open build/PulseMonitor.app
```

### Windows

```powershell
cd Windows
dotnet build PulseMonitor.sln -c Release -p:Platform=x64
dotnet run --project PulseMonitor.Windows -c Release -p:Platform=x64
```

## Privacy

No telemetry, no analytics, no account. History and sync bundles stay on disk
under Application Support (macOS) or LocalAppData (Windows).

## License

MIT — see [LICENSE](LICENSE)

# PulseMonitor

Premium macOS performance monitoring and diagnostic suite — built to explain **why** a Mac is slow, not just show percentages.

![Platform](https://img.shields.io/badge/macOS-14%2B%20Sonoma-blue)
![Language](https://img.shields.io/badge/Swift-6-orange)
![UI](https://img.shields.io/badge/SwiftUI-Charts-green)
![Privacy](https://img.shields.io/badge/Telemetry-None-success)

## Highlights

- **Intelligent bottleneck engine** — CPU / GPU / memory / thermal / disk / network rules with plain-English explanations
- **Apple Silicon aware** — separate Performance and Efficiency core heat maps
- **Historical SQLite logging** — scrub backwards through time with retention controls
- **Game detector** — Steam, Minecraft, Whisky/Wine, emulators (Ryujinx, RPCS3, PCSX2, Dolphin, Cemu, Yuzu forks…)
- **Process explorer** — CPU, RAM, threads, energy, architecture, path, kill / reveal
- **Menu bar widget** — selectable live metric
- **Local-only** — no telemetry, no analytics, no internet required
- **Exports** — JSON, CSV, PDF diagnostic reports

## Architecture

```
MVVM + Services + Repository + Dependency Injection
Async/Await · Actors · Observation · Swift Charts
```

| Layer | Responsibility |
|--------|----------------|
| `Services/` | Low-overhead Mach / IOKit / sysctl / Metal / libproc sampling |
| `Analysis/` | Rule engine + game detector + explanation generator |
| `ViewModels/` | `@Observable` presentation state |
| `Views/` | SwiftUI modules (Dashboard, CPU, GPU, Memory, …) |
| `HistoryRepository` | SQLite retention store |

## Requirements

- macOS 14 Sonoma or later
- Xcode 16+ (Swift 6)
- Intel or Apple Silicon Mac

## Build & Run

```bash
open PulseMonitor.xcodeproj
```

Select the **PulseMonitor** scheme → **My Mac** → Run (⌘R).

Sandbox is disabled so host statistics, process listing, and disk counters work correctly. The app still performs **zero network I/O**.

## Design goals

| Goal | Target |
|------|--------|
| CPU overhead | < 2% |
| Memory | < 200 MB |
| Refresh | Configurable 0.5s–5s (default 1s) |
| Privacy | Fully offline |

## Modules

Dashboard · CPU · GPU · Memory · Thermal · Storage · Network · Battery · Processes · History · Games · Analysis · Reports · Settings · Menu Bar

## Disclaimer

Some sensors (die temperature, fan RPM, precise GPU power, SMART details) require Apple private APIs or elevated helpers. PulseMonitor prefers **public Apple APIs** (`host_statistics`, `ProcessInfo.thermalState`, IOKit power sources, Metal, libproc, `getifaddrs`) and degrades gracefully when a reading is unavailable — while still diagnosing bottlenecks from thermal state, utilization patterns, swap, and process behavior.

## License

MIT — see [LICENSE](LICENSE)

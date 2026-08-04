# PulseMonitor — Windows Edition (v4)

WinUI 3 / Windows App SDK shell over `PulseMonitor.Core`, which samples hardware
through official Windows APIs (PDH, WMI, Win32, Event Log).

## Requirements

- Windows 10 1809+ or Windows 11
- [Visual Studio 2022](https://visualstudio.microsoft.com/) with **.NET desktop development** and **Windows App SDK** workloads
- .NET 8 SDK

## Build

```powershell
cd Windows
dotnet restore PulseMonitor.sln
dotnet build PulseMonitor.sln -c Release -p:Platform=x64
dotnet run --project PulseMonitor.Windows -c Release -p:Platform=x64
```

The app is unpackaged (`WindowsPackageType=None`) for simpler local runs.

## Layout

| Project | Role |
|---------|------|
| `PulseMonitor.Core` | HAL, sensors, analytics, reports, sync (no UI) |
| `PulseMonitor.Windows` | WinUI 3 navigation shell |

Shared JSON contracts live in `../Shared/Schemas/`.

## Honesty

Fan write, RGB apply, overclock apply, RT/tensor utilization, and PSU telemetry
are capability-gated. Missing vendor bridges show **unsupported** with a reason —
never invented sliders or temperatures.

# PulseMonitor Cross-Platform Architecture (v5 — Athena)

```
┌─────────────────────────────────────────────────────────────┐
│                     UI Layer                                │
│  macOS: SwiftUI          Windows: WPF / WinUI               │
│  AI Copilot Dashboard (Athena)                              │
└───────────────────────────┬─────────────────────────────────┘
                            │
┌───────────────────────────▼─────────────────────────────────┐
│        Performance Intelligence Engine (PIE)                │
│  Insight · Prediction · Recommendation · Pattern            │
│  Timeline · Optimization · NL · Learning · Reports · Knowledge│
└───────────────┬─────────────────────────────┬───────────────┘
                │                             │
┌───────────────▼──────────────┐ ┌────────────▼────────────────┐
│  Hardware Abstraction (HAL)  │ │  Sensor Layer               │
└──────────────────────────────┘ └─────────────────────────────┘
```

## Honesty

PIE never fabricates sensors. Predictions are linear trend estimates and are labeled `isEstimate`. Unavailable paths return explicit reasons.

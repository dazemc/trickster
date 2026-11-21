---
title: Trickster
description: A Flutter-native Wayland status bar for other people's compositors.
---

Denial owns the desktop. **Trickster just visits.**

Trickster takes Denial's system bar — the floating pills, the accent, the motion — and runs it as a guest on other compositors: one thin layer-shell strip per display, no compositor attached.

## At a glance

- One Flutter Linux process, one `wlr-layer-shell` surface per output (plus one transient overlay surface per open tray menu, tooltip, or clock calendar).
- Denial-parity modules: clock, battery, media, tray, CPU/GPU, workspaces.
- OpenCode usage: the local server's Go allowance windows and the newest
  session's tokens and cost.
- RAM: a 1 Hz `/proc/meminfo` meter with thresholds, captions, and a
  sparkline (user-requested addition, not Denial parity).
- VRAM: a per-GPU dedicated-memory meter from sysfs or NVML, sharing the GPU
  sampler (user-requested addition, not Denial parity).
- Temperature: a hwmon Celsius meter with CPU-sensor priority and a hottest
  fallback (user-requested addition, not Denial parity).
- Disk: a 30 s statvfs meter for one configured mount, with IEC used/total/free
  detail on hover (user-requested addition, not Denial parity).
- Keyboard layout: a Hyprland event-driven KB pill with the full layout set on
  hover (user-requested addition, not Denial parity).
- Denial-style files-on-disk config with live reload and a `--check` preflight.
- Sway, Hyprland, niri, river, and COSMIC targets.

```text
Host compositor ──> layer-shell strip ──> Flutter scene (one surface per output)
          input <──── interactivity modes <──── pill hit regions <────┘
                                                                   │
Displays <────────────── host composition <────────────── client buffers
```

<Info>
Trickster is in early development (v0.2.2). Modules, config schema, and the control protocol can still change before 1.0.
</Info>

## Where to go next

- [Installation](/installation) — build from source and run your first bar.
- [Configuration](/configuration) — `session.conf`, `outputs.conf`, `settings.json`.
- [Modules](/modules) — what each pill does and how to build a new one.
- [Architecture](/architecture) — guest model, frame path, and what was ported from Denial.
- [CLI reference](/cli) — `trickster` and `tricksterctl`.
- [Development](/development) — build, test, packaging, and project rules.

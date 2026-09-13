---
title: Trickster
description: A Flutter-native Wayland status bar for other people's compositors.
---

Denial owns the desktop. **Trickster just visits.**

Trickster takes Denial's system bar — the floating pills, the accent, the motion — and runs it as a guest on other compositors: one thin layer-shell strip per display, no compositor attached.

## At a glance

- One Flutter Linux process, one `wlr-layer-shell` surface per output.
- Denial-parity modules: clock, battery, media-planned, tray-planned, CPU/GPU, workspaces.
- Denial-style files-on-disk config with live reload and a `--check` preflight.
- Sway, Hyprland, niri, river, and COSMIC targets.

```text
Host compositor ──> layer-shell strip ──> Flutter scene (one surface per output)
          input <──── interactivity modes <──── pill hit regions <────┘
                                                                   │
Displays <────────────── host composition <────────────── client buffers
```

<Info>
Trickster is in early development (v0.1.0). Modules, config schema, and the control protocol can still change before 1.0.
</Info>

## Where to go next

- [Installation](/installation) — build from source and run your first bar.
- [Configuration](/configuration) — `session.conf`, `outputs.conf`, `settings.json`.
- [Modules](/modules) — what each pill does and how to build a new one.
- [Architecture](/architecture) — guest model, frame path, and what was ported from Denial.
- [CLI reference](/cli) — `trickster` and `tricksterctl`.
- [Development](/development) — build, test, packaging, and project rules.

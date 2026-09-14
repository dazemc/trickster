# Porting from Denial to Trickster

Domain knowledge subordinate to `AGENTS.md` and `.llm/workflow.md` (see
`AGENTS.md` → Instruction precedence); on a conflict the higher document wins
and this file is corrected.

When a Denial file is compositor-agnostic, port it. When it is not, write
the smallest honest replacement and keep the same type names at the module
boundary so the widgets do not care.

Port: pill cards, theme tokens, motion, clock, UPower, MPRIS, SNI tray
service, CPU/GPU status, settings store shape, `system_bar=` grammar,
layout strip math.

Replace: `denial_bridge` workspaces → compositor IPC; wallpaper accent →
configured color plus the optional local sampler (`accent_source`, reading
the host's awww/swww wallpaper cache); XEmbed tray → omit; exclusive zone →
layer-shell request.

Do not add features Denial's bar does not have until parity is real.

Deliberate, user-reviewed divergences:

- **Per-module placement.** The user asked for a settings control that
  assigns each module to the strip's leading, center, or trailing zone;
  Denial hardcodes tray/workspaces/the rest. Do not remove it for parity.
- **Meter captions.** CPU and NVIDIA GPU meters default to `CPU`/`GPU`,
  with queried device names (`/proc/cpuinfo` model name, NVML device name)
  kept in state for the future caption option; AMD/Intel pips keep their
  vendor tags. NVIDIA therefore diverges from Denial's `NV`. Do not restore
  `NV`, or make device names the default, without asking.

## Reference tree

Reviewed against the Denial checkout at `271aecd` (`v0.4.0`, 2026-09-13),
expected at `~/GitHub/denial` (`dart_shell/`, `settings_app/`). The original
ports came from the `v0.3.1` line; a checkout may still sit at
`85b2303` (`v0.3.1`, 2026-08-31) — fetch tags before porting. Record a new
revision here whenever a port comes from a different tree, so a later
session never ports against drift.

The v0.4.0 review found no drift in the ported services (UPower/battery,
MPRIS, StatusNotifier, CPU/GPU), the settings store, localization, wallpaper
accent, theme tokens, or the `system_bar=` grammar. What moved:

- The bar gained a centered workspace rail
  (`desktop_workspace_indicator.dart`, added in `fdb986e`, 2026-09-02):
  numbered pips in a card with a liquid active lens. Trickster ported it
  (centered indicator slot, numbered pips, dark lens,
  takeoff/travel/settle deformation, and Denial's fixed 1..count rail on
  every monitor: `workspaces.workspace_count`, with active and occupied
  resolved against each output).
- `Motion` gained `workspaceIndicatorTakeoff` / `Travel` / `Settle` and the
  MD3 emphasized accelerate/decelerate curves; `springTo` now passes
  `snapToEnd: true` (Trickster has no spring paths to fix).
- Appearance moved to `ShellTransparencyMode` (off/blur/glass) with a glass
  engine, and the displays page's scale control became a canonicalized
  percent field. Both are compositor/glass work outside the honest
  layer-shell replacement, as are the new compositor layout settings
  (scrolling layout, workspace count/orientation, suspend mode).

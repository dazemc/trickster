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
configured color plus optional local sampler; XEmbed tray → omit; exclusive
zone → layer-shell request.

Do not add features Denial's bar does not have until parity is real.

Deliberate, user-reviewed divergences:

- **Meter captions.** CPU and NVIDIA GPU meters default to `CPU`/`GPU`,
  with queried device names (`/proc/cpuinfo` model name, NVML device name)
  kept in state for the future caption option; AMD/Intel pips keep their
  vendor tags. NVIDIA therefore diverges from Denial's `NV`. Do not restore
  `NV`, or make device names the default, without asking.

## Reference tree

Ports were taken from the Denial checkout at
`85b2303e2f09ae7b7b993641f90061a200f03d53` (`v0.3.1`, 2026-08-31), expected
at `~/GitHub/denial` (`dart_shell/`, `settings_app/`). Record a new revision
here whenever a port comes from a different tree, so a later session never
ports against drift.

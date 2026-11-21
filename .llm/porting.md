# Porting from Denial to Trickster

Domain knowledge subordinate to `AGENTS.md` and `.llm/workflow.md` (see
`AGENTS.md` → Instruction precedence); on a conflict the higher document wins
and this file is corrected.

When a Denial file is compositor-agnostic, port it. When it is not, write the
smallest honest replacement and keep the same type names at the module boundary
so the widgets do not care.

## Ported today

- Pill cards, theme tokens, motion constants and curves.
- Clock behavior, including minute alignment and seconds cadence.
- MPRIS playback state and controls.
- StatusNotifier tray service, menus, icon lookup, and menu model.
- CPU/GPU status shapes and meters.
- Settings-store shape: revision, expected-revision retry, last-good.
- `system_bar=` grammar and layout strip math.
- Localization shape and the accent model.

## Replaced honestly

- `denial_bridge` workspaces → Sway/i3, Hyprland, and niri IPC backends.
- Wallpaper accent → configured color plus the optional local sampler
  (`accent_source`, reading the host's awww/swww cache; grim fallback for
  outputs without a cache image).
- XEmbed tray → omitted. Denial's XEmbed merge came from owning Xwayland; a
  layer-shell guest cannot borrow it.
- Exclusive zone → layer-shell request.
- Compositor glass engine → capability-gated `ext-background-effect` blur over
  the pill bounds, or a translucent gradient fallback.

## Not ported — current gaps

- **UPower battery.** Denial's bar speaks UPower; Trickster's battery module
  reads `/sys/class/power_supply` synchronously every 5 s. The UPower service
  shape is an open gap, not current behavior. Do not describe the battery as
  UPower until the migration lands and is proven.
- **Native workspace state.** Denial owns workspace placement and persistence;
  Trickster mirrors the compositor and cannot create, destroy, or persist
  workspaces.
- **Compositor glass.** Refraction, dispersion, and the full glass engine stay
  behind. Trickster approximates the look without owning KMS.
- **XEmbed tray.** Out of scope for a guest.

## Deliberate, user-reviewed divergences

- **Per-module placement.** A settings control assigns each module to the
  strip's leading, center, or trailing zone; Denial hardcodes the layout.
  Do not remove it for parity.
- **Meter captions.** CPU and NVIDIA GPU meters default to `CPU`/`GPU`, with
  queried device names kept for a future caption option. AMD/Intel pips keep
  vendor tags. NVIDIA therefore diverges from Denial's `NV`; do not restore
  `NV` or make device names the default without asking.
- **Workspace rail.** The rail is centered, numbered, and per-output, using
  the workspaces the compositor places on that output. A layer-shell guest
  does not own placement, persistence, or the main display.
- **Glass approximation.** Pill-region blur, dark backing, and a painted rim
  sheen stand in for Denial's compositor glass. Do not raise the fill toward
  opaque or delete the sheen without asking.
- **OpenCode module.** A non-Denial addition for the local OpenCode usage
  windows and newest session's tokens/cost. It reads OpenCode's local server
  and is not part of bar parity.
- **RAM, VRAM, temperature, and disk modules.** User-requested additions;
  Denial has no memory, temperature, or disk module. RAM reads
  `/proc/meminfo`; VRAM rides the shared GPU sampler; temperature reads hwmon
  with a CPU-sensor preference; disk reads one configured mount over
  statvfs. All four are default-on. Do not present them as Denial parity or
  infer them from Denial's CPU/GPU status shapes.
- **Keyboard layout.** A user-requested Hyprland-only module reading
  `j/devices` plus `activelayout` events from `.socket2.sock`. Sway and niri
  backends are not implemented yet. Denial owns input directly; do not
  describe this as Denial parity.
- **Network.** A user-requested kernel-only pill. Denial's bar has no network
  module; its NetworkManager/iwd service feeds the quick-settings connectivity
  surface. Trickster's first slice reads one selected physical interface from
  `/sys/class/net`, the IPv4/IPv6 default-route tables, and `/proc/net/dev`,
  and never spawns `nmcli` or `iw`. SSID, signal, band, and connectivity
  metadata are a later slice, not current behavior. Do not present the
  kernel-only pill as Denial parity.
- **Settings application.** Same binary in settings mode, separate process and
  engine, covering exactly the settings the bar owns — never compositor
  controls it does not own.

## Reference tree

Reviewed against the Denial checkout at `271aecd` (`v0.4.0`, 2026-09-13),
expected at `~/GitHub/denial` (`dart_shell/`, `settings_app/`). The original
ports came from the `v0.3.1` line; a checkout may still sit at `85b2303`
(`v0.3.1`, 2026-08-31) — fetch tags before porting. Record a new revision here
whenever a port comes from a different tree, so a later session never ports
against drift.

The v0.4.0 review found no drift in the ported services (MPRIS, StatusNotifier,
CPU/GPU), the settings store, localization, wallpaper accent, theme tokens, or
the `system_bar=` grammar. What moved:

- The bar gained a centered workspace rail with a liquid active lens; Trickster
  ported the indicator slot, numbered pips, dark lens, and
  takeoff/travel/settle deformation.
- `Motion` gained the workspace indicator timings and MD3 emphasized curves;
  Trickster has no spring paths to fix.
- Appearance moved to a compositor glass engine and compositor layout
  settings. Both are outside the honest layer-shell replacement.

## Port performance and lifecycle too

A port is not finished when the pixels match. When porting a Denial widget or
service:

- preserve its idle behavior, not just its visual state;
- add no interval poll where D-Bus signals or compositor events can push;
- keep blocking OS work on a widget-free worker isolate;
- dispose every subscription, socket, D-Bus client, isolate, and decoded image
  in the same scope that created it;
- keep caches bounded and images decoded at display size;
- record any divergence in `.llm/suggestions.md` if it changes cost or
  lifecycle.

## Rule of scope

Do not add features Denial's bar does not have until parity is real. The
divergences listed above are explicit user decisions; they are not a license
for new modules or new compositor controls.

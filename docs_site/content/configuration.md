---
title: Configuration
description: session.conf, outputs.conf, settings.json, and live reload semantics.
---

Trickster is configured like Denial: files on disk, `KEY=VALUE` with `#` comments. The `TricksterBar` Dart API is the typed in-memory model these files decode into — not the user interface.

## Layers

### Machine environment — `/etc/trickster/session.conf`

Parsed by the Dart bootstrap at startup. Packaged template, `backup=`-preserved.

```sh
# TRICKSTER_LAYER=top
# TRICKSTER_NAMESPACE=trickster
# TRICKSTER_KEYBOARD=on_demand
# TRICKSTER_OUTPUT_CONFIG=/home/example/.config/trickster/outputs.conf
# TRICKSTER_ACCENT=#d0bcff
# TRICKSTER_LOG=trickster=info
```

| Key | Values | Default |
| --- | --- | --- |
| `TRICKSTER_LAYER` | `background`, `bottom`, `top`, `overlay` | `top` |
| `TRICKSTER_NAMESPACE` | layer-shell namespace string | `trickster` |
| `TRICKSTER_KEYBOARD` | `none`, `exclusive`, `on_demand` | `on_demand` |
| `TRICKSTER_OUTPUT_CONFIG` | path to an `outputs.conf` | XDG default |
| `TRICKSTER_ACCENT` | `#RRGGBB` machine accent override | unset |
| `TRICKSTER_LOG` | log filter | unset |

Process environment wins over the file for the same key.

### Bar placement — `~/.config/trickster/outputs.conf`

Denial's `system_bar=` grammar, verbatim. Template copied on first launch, never overwritten.

```sh
# system_bar=top,32
# system_bar=bottom,40,eDP-1
# system_bar=hidden
```

The third field and beyond select connectors; with no connectors the bar lands on every output. Thickness is clamped so a misconfigured value can never swallow an output, and it becomes the layer-shell exclusive zone.

### Settings — `~/.config/trickster/settings.json`

Versioned document with Denial's revision discipline: one async write queue, `expectedRevision` check-and-retry, current plus last-good snapshot only.

```json
{
  "revision": 1,
  "accent": "#d0bcff",
  "modules": ["workspaces", "cpu", "gpu", "battery", "clock"]
}
```

### Module options

The `modules` list enables the modules and sets their order inside each
placement zone; `module_placement` decides the zone, defaulting to the tray
leading, the workspace rail centered, and the rest trailing.

Each module reads typed options from the same document. Invalid values are
rejected at decode, so a live reload keeps the last-good settings.

- `accent_source` (`custom` or `wallpaper`, default `custom`) — where the
  accent comes from. `wallpaper` samples the host wallpaper's dominant
  color from the awww/swww cache and follows wallpaper changes, falling back
  to a `grim` capture of the strip band when an output has no cache image;
  the bar starts no sampler unless this source asks for one.
- `accent_wallpaper_pick` (`#RRGGBB`, optional) — with the wallpaper
  source, the extracted candidate closest in hue; the dominant candidate
  applies when absent. The settings application lists the palette with
  copyable hex values.
- `display_appearance` (optional object keyed by connector) — per-display
  overrides of the accent keys; a missing key falls back to the global one.
- `appearance.blur` (bool, default `true`) — when false the pills keep the
  opaque fill even if the host advertises `ext-background-effect`.
- `module_placement` (optional object) — per-module zone along the strip's
  main axis: `leading`, `center`, or `trailing`. Defaults: the tray leads,
  the workspace rail centers, and every other module trails. The settings
  application exposes the same choice per module.
- The workspace rail mirrors the compositor: each strip shows the numbered
  workspaces the compositor places on its output, in id order, and pressing
  a pip focuses it. Placement, persistence, and the main display belong to
  the compositor. On Hyprland, pin and keep a range with workspace rules,
  e.g. `workspace = 1, monitor:HDMI-A-1, persistent:true`. The retired
  `workspaces` counts, per-output lengths, and display order are ignored on
  decode; the section now holds only the pip look:
  `workspaces.pip_style` (`number`, `dot`, `roman`, `image`, default
  `number`), `workspaces.image_source` (one browsed file for every pip),
  `workspaces.image_by_workspace` (workspace name to file), and
  `workspaces.tint_svg` (bool; recolor SVG artwork with the accent).
- `clock.format` (`locale`, `24h`, or `12h`, default `locale`) — force the
  clock's hour cycle instead of following the locale's preference;
  `clock.show_date` (bool, default `true`), `clock.show_seconds` (bool;
  the clock then ticks every second instead of once a minute), and
  `clock.date_style` (`short`, `long`, or `weekday`, default `short`).
- `cpu.warn` / `cpu.critical` and `gpu.warn` / `gpu.critical` (number 0–1,
  defaults `0.85` / `0.95`) — tint the load percent when it crosses each
  level; `warn` must stay below `critical`.
- `cpu.warn_color` / `cpu.critical_color` and the `gpu.*` pair (`#RRGGBB`,
  optional) — override the default warning and danger tints; the settings
  application picks them on the same color wheel as the accent.
- `cpu.caption_source` / `gpu.caption_source` (`generic`, `device`, or
  `custom`, default `generic`) — label each meter with its generic tag, the
  queried device name, or the typed `caption_prefix`.
- `cpu.sparkline` / `gpu.sparkline` (bool, default `true`) — hide the
  recent-history sparkline.
- `battery.warn` / `battery.critical` (int 1–100, defaults `20` / `10`) —
  tint the battery gauge and percent while discharging; `critical` must stay
  below `warn`.
- `media.mode` (`full`, `semi`, or `compact`, default `semi`) — full shows
  the equalizer, now-playing text, and transport keys; semi the equalizer
  and keys; compact only the keys. Right-clicking the pill cycles the modes
  transiently; the configured mode returns on relaunch.
- The retired `meter` object (shared caption source and sparkline) is read
  once as a fallback for `cpu` and `gpu` and never written again.


## Live reload

A file watcher (200ms debounce) applies edits without restarting:

- **Hot keys** — accent, module list/order, clock format, thresholds. Providers rebuild; surfaces untouched.
- **Disruptive keys** — edge, layer, exclusive size, output set. Only the affected layer surface is destroyed and recreated.

<Warning>
An invalid file keeps the last-good state and logs the error. The bar never crashes on config.
</Warning>

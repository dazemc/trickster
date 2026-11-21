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
```

| Key | Values | Default |
| --- | --- | --- |
| `TRICKSTER_LAYER` | `background`, `bottom`, `top`, `overlay` | `top` |
| `TRICKSTER_NAMESPACE` | layer-shell namespace string | `trickster` |
| `TRICKSTER_KEYBOARD` | `none`, `exclusive`, `on_demand` | `on_demand` |
| `TRICKSTER_OUTPUT_CONFIG` | path to an `outputs.conf` | XDG default |
| `TRICKSTER_ACCENT` | `#RRGGBB` machine accent override | unset |

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
  "modules": ["workspaces", "cpu", "gpu", "vram", "ram", "temperature", "disk", "battery", "clock"]
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
  opaque fill even if the host advertises `ext-background-effect`; the clock
  calendar's panel follows the same choice.
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
  `workspaces.image_by_workspace` (workspace name to file; an entry whose
  workspace no longer exists is ignored), and
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
- `ram.warn` / `ram.critical` (number 0–1, defaults `0.85` / `0.95`) — tint
  the used-memory percent when it crosses each level; `warn` must stay below
  `critical`.
- `ram.warn_color` / `ram.critical_color` (`#RRGGBB`, optional) — override
  the default warning and danger tints.
- `ram.caption_source` (`generic` or `custom`, default `generic`) and
  `ram.caption_prefix` — label the meter with `RAM` or the typed prefix. RAM
  has no device-name source.
- `ram.sparkline` (bool, default `true`) — hide the recent-history sparkline.
- `ram` is enabled in the default module list; a document that explicitly
  lists `modules` keeps that list, so an existing setup only gains the pill
  when its list includes `ram`.
- `vram.warn` / `vram.critical` (number 0–1, defaults `0.85` / `0.95`) — tint
  the dedicated-memory percent when it crosses each level; `warn` must stay
  below `critical`.
- `vram.warn_color` / `vram.critical_color` (`#RRGGBB`, optional) — override
  the default warning and danger tints.
- `vram.caption_source` (`generic`, `device`, or `custom`, default `generic`)
  and `vram.caption_prefix` — label each GPU with `VRAM`, its queried device
  name (NVIDIA), or the typed prefix.
- `vram.sparkline` (bool, default `true`) — hide the recent-history sparkline.
- `vram` is enabled in the default module list and renders only on GPUs that
  publish dedicated memory; existing explicit `modules` lists keep their
  contents.
- `temperature.warn` / `temperature.critical` (number of °C, defaults `80` /
  `95`) — tint the reading when it crosses each level; `warn` must stay below
  `critical`.
- `temperature.warn_color` / `temperature.critical_color` (`#RRGGBB`,
  optional) — override the default warning and danger tints.
- `temperature.caption_source` (`generic` or `custom`, default `generic`) and
  `temperature.caption_prefix` — label the meter `CPU` for a CPU sensor,
  `TEMP` for a fallback sensor, or the typed prefix.
- `temperature.sparkline` (bool, default `true`) — hide the recent-history
  sparkline.
- `temperature` is enabled in the default module list and hides when no hwmon
  sensor is readable.
- `disk.path` (absolute mount path, default `/`) — the mount sampled with
  `statvfs` every 30 s on a worker isolate.
- `disk.warn` / `disk.critical` (number 0–1, defaults `0.80` / `0.95`) — tint
  the used fraction when it crosses each level; `warn` must stay below
  `critical`.
- `disk.warn_color` / `disk.critical_color` (`#RRGGBB`, optional) — override
  the default warning and danger tints.
- `disk.caption_source` (`generic` or `custom`, default `generic`) and
  `disk.caption_prefix` — label the meter `DISK` or the typed prefix. The
  hover tooltip carries used, total, and free in IEC units.
- `disk` is enabled in the default module list and has no sparkline or
  history; it hides when the mount is missing or unreadable.
- `battery.warn` / `battery.critical` (int 1–100, defaults `20` / `10`) —
  tint the battery gauge and percent while discharging; `critical` must stay
  below `warn`.
- `media.mode` (`full`, `semi`, or `compact`, default `semi`) — full shows
  the equalizer, now-playing text, and transport keys; semi the equalizer
  and keys; compact only the keys. Right-clicking the pill cycles the modes
  and saves the choice, so the document and an open settings window follow
  it. `media.bars` (3–12, default 4) sets how many bars the equalizer mark
  paints from the default sink's band levels, and `media.volume_step`
  (1–25, default 5) sets the percent each wheel notch over the volume
  readout moves the sink.
- `opencode.meter` (`rolling`, `weekly`, or `monthly`, default `rolling`) —
  which OpenCode Go allowance window the pill headlines; the hover label
  always carries all three. `opencode.show_cost` (bool, default `true`) —
  append the newest session's cost to the headline. The module reads the
  running server's state document (`$XDG_STATE_HOME/opencode/service.json`)
  and polls the usage limits and newest session once a minute while it is
  configured; a stopped server hides the pill. Clicking the pill launches
  the `opencode-usage` companion window (found in the XDG bin directory,
  `~/.local/bin`, `/usr/local/bin`, `/usr/bin`, or `PATH`), falling back to
  the workspace console URL when it is not installed.
- The retired `meter` object (shared caption source and sparkline) is read
  once as a fallback for `cpu` and `gpu` and never written again.


## Live reload

A file watcher (200ms debounce) applies edits without restarting:

- **Hot keys** — accent, module list/order, clock format, thresholds. Providers rebuild; surfaces untouched.
- **Disruptive keys** — edge, layer, exclusive size, output set. Only the affected layer surface is destroyed and recreated.

<Warning>
An invalid file keeps the last-good state and logs the error. The bar never crashes on config.
</Warning>

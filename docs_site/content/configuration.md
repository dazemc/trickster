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

The third field and beyond select connectors; with no connectors the bar lands on every output. Thickness is a positive logical-pixel band up to 512; the parser rejects a non-finite, zero, negative, or oversized value, so the bar keeps its last-good file instead of accepting a band that could swallow an output. A settings save rewrites only the `system_bar=` line: comments and unrelated keys stay byte-for-byte, the write is atomic (unique temp file plus rename), and the live document is snapshotted to `outputs.conf.prev` for recovery from a torn write. `hidden` forces thickness 0 and releases the exclusive zone; the settings page clears the connector selection when hidden is chosen, so returning to an edge starts from every output at the default thickness. A failed save is reported on the displays page while the bar keeps its previous placement; a control-socket rejection stays on the socket rather than silently rewriting the file, and only genuine transport loss falls back to the file.

### Settings — `~/.config/trickster/settings.json`

Versioned document with Denial's revision discipline: one async write queue, `expectedRevision` check-and-retry, current plus last-good snapshot only.

```json
{
  "revision": 1,
  "accent": "#d0bcff",
  "modules": ["workspaces", "cpu", "gpu", "vram", "ram", "temperature", "disk", "keyboard_layout", "brightness", "battery", "network", "clock"]
}
```

Writes from the bar and the settings window share one revision line and one cross-process lock. If the document changed since the editor loaded it, the save is rejected instead of overwriting the other writer; the editor shows the conflict and reloads the latest document. An unsaved edit survives an external change and still conflicts when saved, so neither writer loses fields silently. Closing the settings window flushes pending settings and display edits first: the close control, the titlebar close, and Alt+F4 all wait for the write to land (with a bounded fallback) before the window disappears, and a failed save never leaves the window unclosable.

A valid live `settings.json` always wins, even when its revision is lower than one seen earlier — a deliberate rollback is honored. The `.prev` snapshot and in-memory copy are used only when the live file is missing, unreadable, or corrupt. A corrupt settings document keeps last-good settings without blocking a valid `outputs.conf` reload, and the settings window never replaces a document it could not load with defaults.

### Module options

The `modules` list enables the modules and sets their order inside each
placement zone; `module_placement` decides the zone, defaulting to the tray
leading, the workspace rail centered, and the rest trailing.

`modules` must be a list of strings. A missing key enables the default module
set; an explicit empty list stays empty. A non-list value or a non-string entry
rejects the document at decode, so the bar keeps last-good settings instead of
silently enabling every module. Duplicate names keep their first occurrence,
and unknown names stay in the document but render nothing.

Each module reads typed options from the same document. Invalid values are
rejected at decode, so a live reload keeps the last-good settings.

The settings application probes the machine before it offers a module: no
battery, no dedicated GPU memory, no readable hwmon temperature sensor, a
missing configured disk path (a mount directory or a file inside the mount),
no physical or pinned network interface, no supported keyboard-layout backend
or no active layout, and no readable backlight each move an enabled row into
an Unavailable section with a reason and a disable toggle. Turning it off
moves it to Disabled with the same reason and its options gear; turning it
back on returns it to Unavailable. A module never appears in both sections.
The probe re-runs when `disk.path` or `network.interface` settles after an
edit and once more when the save completes, so a corrected path or interface
clears its row without reopening the page; a failed probe keeps the last good
answer. Keyboard layout prefers the running bar's control status (a backend
with an active layout) and falls back to the settings process environment.

- `accent_source` (`custom` or `wallpaper`, default `custom`) — where the
  accent comes from. `wallpaper` samples the host wallpaper's dominant
  color from the awww/swww cache and follows wallpaper changes, falling back
  to a `grim` capture of the strip band when an output has no cache image;
  the bar starts no sampler unless this source asks for one. The settings
  window asks a running bar's control status for its already-computed
  candidates and re-asks when the window regains focus, the app resumes, a
  settings save lands, or the wallpaper cache changes — never on a timer. It
  falls back to its own sample immediately when no bar answers, and after a
  bounded retry when a reachable bar has not produced candidates yet. A
  wallpaper change invalidates the cached strip capture; a geometry-only
  refresh may reuse it.
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
- The settings modules page groups rows by zone, drags them between zones
  with edge auto-scroll, and supports `Ctrl+Arrow` reorder plus
  `Ctrl+Shift+Arrow` zone moves from the drag handle. An enabled row follows
  the nearest zone while it is dragged. A disabled row enables and moves only
  when released inside a zone's heading or card; releasing over the page
  header, outside every zone, or back on the Disabled card leaves it disabled
  where it was. A disabled row keeps its options gear; opening it shows a
  right-edge inspector over a modal scrim, and the module page keeps its
  scroll position and width. The page caps its content width at 1120 logical
  pixels and paints a scrollbar at 900×600 and other window sizes; the
  inspector scrolls independently.
- Every settings control is keyboard-operable: Tab moves focus, Enter or
  Space activates buttons, chips, toggles, and navigation rows, and sliders
  step along their scale with the arrow keys. A focused control paints the
  accent ring; selected chips and enabled toggles switch to a contrasting
  ring. Opening the options inspector moves focus into it, keeps Tab inside,
  hides the shell from assistive technology, closes on Escape, and returns
  focus to the gear that opened it. Switching sections returns the page to
  the top.
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
  `clock.date_style` (`short`, `long`, or `weekday`, default `short`). On a
  left or right strip the bar hides the date and seconds regardless of these
  keys; the settings inspector disables both toggles and says why.
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
- `cpu.show_load_average` (bool, default `true`) — append normalized
  1/5/15-minute load averages and the online core count to the CPU tooltip.
- `ram.warn` / `ram.critical` (number 0–1, defaults `0.85` / `0.95`) — tint
  the used-memory percent when it crosses each level; `warn` must stay below
  `critical`.
- `ram.warn_color` / `ram.critical_color` (`#RRGGBB`, optional) — override
  the default warning and danger tints.
- `ram.caption_source` (`generic` or `custom`, default `generic`) and
  `ram.caption_prefix` — label the meter with `RAM` or the typed prefix. RAM
  has no device-name source. The hover tooltip adds swap used, total, and
  percentage when the kernel publishes a swap area.
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
  `statvfs` every 30 s on a worker isolate. The settings field accepts
  absolute paths only, reverts invalid or empty text when it loses focus, and
  its reset control restores `/`.
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
- `keyboard_layout` has no options. It auto-detects Hyprland, Sway, or niri,
  reads the main or first keyboard through that compositor's input listing,
  follows its layout events without polling, and hides without a supported
  backend. It is enabled in the default module list.
- `brightness` has no options. It reads the preferred readable
  `/sys/class/backlight` device at 1 Hz, pauses with the seat, and hides when
  no backlight is readable. It is enabled in the default module list.
- `network.interface` (Linux interface name, optional) — pin one interface,
  including a virtual one, instead of auto-selecting the active physical
  interface. Auto mode ignores loopback and interfaces without a
  `/sys/class/net/<if>/device` link, so tunnels and container veths are never
  sampled or summed. The settings field rejects an invalid Linux name while
  typing, reverts it on focus loss, and its reset control restores auto.
  `network.show_rates` (bool, default `true`) — show the compact
  receive/transmit rates on the pill; the hover tooltip always keeps them.
  `network` is enabled in the default module list and hides only when no
  physical or pinned interface exists. When NetworkManager or iwd owns the
  system bus, its identity and connectivity metadata enriches the pill and
  tooltip; otherwise the kernel link/route reading remains the fallback.
- `battery.warn` / `battery.critical` (int 1–100, defaults `20` / `10`) —
  tint the battery gauge and percent while discharging; `critical` must stay
  below `warn`. The hover tooltip adds the kernel charge state and a
  minute-rounded time to empty or full when the battery publishes usable
  power/current counters.
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


## Bar menu

Right-clicking an empty part of the strip opens a small panel anchored at
that edge. Its **Trickster Settings** entry launches the same executable as a
separate `--settings` process and detaches it, so the bar keeps running. When
the bar has an outputs override (`--config PATH` or
`TRICKSTER_OUTPUT_CONFIG`), the menu forwards it, so the settings window
edits the same `outputs.conf` the bar read.

Pills keep their own secondary-click behavior: media cycles its mode, tray
icons open their D-Bus menu, and a press that lands on a module never reaches
the bar menu. Only one overlay is open at a time: opening a tray menu,
calendar, volume slider, or bar menu dismisses the previous one. Escape or a
press outside the panel closes it.


## Live reload

A file watcher (200ms debounce) applies edits without restarting:

- **Hot keys** — accent, module list/order, clock format, thresholds. Providers rebuild; surfaces untouched.
- **Disruptive keys** — edge, layer, exclusive size, output set. Only the affected layer surface is destroyed and recreated.

<Warning>
An invalid file keeps the last-good state and logs the error. The bar never crashes on config.
</Warning>

# Trickster configuration

Domain knowledge subordinate to `AGENTS.md` and `.llm/workflow.md` (see
`AGENTS.md` → Instruction precedence); on a conflict the higher document wins
and this file is corrected.

Status words: **Current** is verified in the tree; **Gap** is tracked in
`.llm/suggestions.md`; **Aspiration** is not shipped behavior.

## Precedence

**Current.** Files use Denial-style `KEY=VALUE` with `#` comments.

1. `/etc/trickster/session.conf` supplies machine defaults.
2. `TRICKSTER_*` environment variables override the file per key.
3. `--config PATH` overrides the `outputs.conf` path for one run.
4. `--edge SIDE` overrides only the strip side for one run.
5. `--check` parses strictly; normal startup keeps last-good state and logs.

The settings document path is always
`$XDG_CONFIG_HOME/trickster/settings.json`; `--config` does not move it.

## `/etc/trickster/session.conf`

| Key | Values | Default |
| --- | --- | --- |
| `TRICKSTER_LAYER` | `background`, `bottom`, `top`, `overlay` | `top` |
| `TRICKSTER_NAMESPACE` | layer-shell namespace string | `trickster` |
| `TRICKSTER_KEYBOARD` | `none`, `exclusive`, `on_demand` | `on_demand` |
| `TRICKSTER_ACCENT` | `#RRGGBB` machine accent override | unset |
| `TRICKSTER_OUTPUT_CONFIG` | path to an `outputs.conf` | XDG default |
| `TRICKSTER_LOG` | log filter | unset |

An invalid `session.conf` is ignored with a log line and defaults are used.
`TRICKSTER_LOG` is parsed into `SessionConfig` but never applied to a logger;
that is a **gap**, not a working filter.

## `$XDG_CONFIG_HOME/trickster/outputs.conf`

Denial's `system_bar=` grammar, verbatim:

```text
system_bar=top,32
system_bar=bottom,40,eDP-1
system_bar=hidden
```

- First value: side (`top`, `bottom`, `left`, `right`, `hidden`).
- Optional second value: thickness in logical pixels; must be positive.
- Remaining values: connector names. An empty list means every output.
- `hidden` forces thickness 0 and releases the exclusive zone; the strip is
  unmapped.
- Unknown keys are ignored. A malformed line is a `FormatException`.
- The per-user file is seeded once from `/etc/trickster/outputs.conf` (or the
  built-in template) and never overwritten after that.
- Strip math ports Denial's `display_layout.dart`; thickness clamps to half the
  output, and the work area becomes the layer-shell exclusive zone.

## `$XDG_CONFIG_HOME/trickster/settings.json`

**Current.** A versioned JSON document owned by the bar. `revision` must be a
positive integer; the bar and settings application share one revision line.
Unknown keys are ignored. Retired workspace counts, per-output overrides, and
display order are ignored on decode because workspace placement belongs to the
compositor.

The document carries:

- `modules`: the configured module names, in strip order;
- `module_placement`: leading/center/trailing zone per module;
- `accent`, `accent_source`, `accent_wallpaper_pick`;
- `display_appearance`: per-connector appearance overrides;
- `appearance`, `workspaces`, `cpu`, `clock`, `battery`, `gpu`, `media`,
  `opencode`: nested module options;
- `locale`: `en` or `zh`; null follows the system.

Every write is revision-checked. A mismatch is a `StateError`; the store
retries once and never keeps a document history. The settings application
selects a transport at startup: the control socket when the bar answers,
otherwise the file transport. It does not switch transports mid-session if the
bar exits.

**Persistence.** The file transport keeps the current document plus one
last-good copy. A write snapshots the last document known to decode
(`_lastGood`) into `.prev` through `.prev.tmp` and an atomic rename, then
writes the live document through `.tmp` and renames it into place. It never
copies the possibly corrupt live file into `.prev`. A read tries the live
document, then `.prev`, then the in-memory last-good copy. This is current +
last-good + one previous snapshot, not a history.

**Gaps.**

- The settings application chooses its transport at startup. If the bar exits
  while the window is open, later saves do not fall back to the file transport.
- A settings document with an invalid scalar type is an invalid document and
  falls back to defaults in normal startup; `--check` still fails it.

## Live reload

**Current.** A `dart:io` watcher on the config directory debounces 200 ms and
reloads through the bootstrap path. A watch stream that errors or closes is
replaced after 500 ms, doubling to a 5 s cap; dispose is terminal. An invalid
file logs and keeps last-good state; the bar never crashes over config.

- **Hot keys** (accent, module list/order, clock format, thresholds) rebuild
  providers.
- **Disruptive keys** (edge, layer, thickness, keyboard, output set) destroy
  and recreate only the affected layer surfaces.
- **Gap:** a non-disruptive settings change still calls native `outputs()`, a
  Wayland enumeration, even when output placement did not change.

## CLI and control socket

**Current.**

- `trickster --check` validates Wayland, `outputs.conf`, `settings.json`,
  layer-shell, blur capability, idle-notify, and outputs; it exits the process
  because the GTK loop outlives `main`.
- `trickster --version`, `--config PATH`, `--edge SIDE`.
- `trickster --settings` runs the settings application: separate process,
  separate engine, no strip surfaces.
- `tricksterctl status|reload|version` speaks one JSON request/reply line over
  `$XDG_RUNTIME_DIR/trickster/control.sock`.
- The control client times out after 2 s. The server probes a live socket
  before binding and unlinks only a socket it owns.
- The server also serves `settings.read/write` and `outputs.read/write` for the
  settings application.

## Ownership map

| File | Typed owner | Transport |
| --- | --- | --- |
| `session.conf` | `SessionConfig` | read-only at startup |
| `outputs.conf` | `OutputsConfig` | file, or control socket from settings |
| `settings.json` | `BarSettings` | settings store, socket-first/file fallback |
| control socket | `ControlServer` | one JSON line per request |

No second writer and no second revision line. The bar's own writes go through
the same settings store instance the control socket serves.

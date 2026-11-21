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

An invalid `session.conf` is ignored with a log line and defaults are used.

## `$XDG_CONFIG_HOME/trickster/outputs.conf`

Denial's `system_bar=` grammar, verbatim:

```text
system_bar=top,32
system_bar=bottom,40,eDP-1
system_bar=hidden
```

- First value: side (`top`, `bottom`, `left`, `right`, `hidden`).
- Optional second value: thickness in logical pixels; must be finite,
  positive, and at most 512 (`OutputsConfig.maxThickness`). The bound applies
  to every value that arrives through the file, so the raw layer-shell request
  is at most 512; `stripWithin`'s separate half-output clamp is preview/test
  geometry and has no production caller yet.
- Remaining values: connector names. Names are trimmed, deduplicated by first
  occurrence, and must not be empty. An empty list means every output.
- `hidden` forces thickness 0 and releases the exclusive zone; the strip is
  unmapped and the grammar carries no connector selection. The settings page
  clears its connector selection on entering hidden, and leaving hidden starts
  from the default thickness with every output selected.
- Unknown keys are ignored. A malformed line, including a non-finite,
  non-positive, oversized, or empty-connector value, is a `FormatException`.
- The per-user file is seeded once from `/etc/trickster/outputs.conf` (or the
  built-in template) and never overwritten after that.
- A settings write merges only the `system_bar=` line: comments and unrelated
  keys survive byte-for-byte, the first existing line is replaced (duplicates
  collapse), or one is inserted. Writes are atomic through a unique temp file
  and rename; the previous valid document is snapshotted to
  `outputs.conf.prev` (one snapshot, no history), and reads fall through the
  live file to `.prev` to defaults, so a torn live file never resets placement
  while a good snapshot exists. An invalid document is rejected before either
  file changes.
- The settings application still prefers the bar's control socket. A
  server-side rejection (`OutputsRequestException`) is surfaced on the
  displays page while the socket stays in use; only a `ControlSocketException`
  (genuine transport loss) flips permanently to the file.
- Strip math ports Denial's `display_layout.dart`; the work area becomes the
  layer-shell exclusive zone. `stripWithin`'s half-output clamp has no
  production caller; the 512 file bound is what limits the live request.

## `$XDG_CONFIG_HOME/trickster/settings.json`

**Current.** A versioned JSON document owned by the bar. `revision` must be a
positive integer; the bar and settings application share one revision line.
Unknown keys are ignored. Retired workspace counts, per-output overrides, and
display order are ignored on decode because workspace placement belongs to the
compositor.

The document carries:

- `modules`: the configured module names, in strip order. Must be a list of
  strings: a missing key defaults to `knownModules`, an empty list stays
  empty, and a non-list value or a non-string entry throws `FormatException`
  instead of silently defaulting. Duplicates keep their first occurrence;
  unknown names stay in the document but render and start nothing.
- `module_placement`: leading/center/trailing zone per module;
- `accent`, `accent_source`, `accent_wallpaper_pick`;
- `display_appearance`: per-connector appearance overrides;
- `appearance`, `workspaces`, `cpu`, `ram`, `temperature`, `disk`, `clock`,
  `battery`, `gpu`, `vram`, `media`, `opencode`: nested module options;
- `locale`: `en` or `zh`; null follows the system.

Every write is revision-checked against a fresh read of the live document.
A mismatch is a `SettingsRevisionConflict`; the store adopts the other
writer's revision, the editor reloads that document, and the user retries
deliberately. A draft preview still owns the editor on an external change: the
reload reports the conflict and keeps the edit; the eventual save re-reads and
conflicts instead of replacing the newer document. A successful external
reload clears a prior conflict error. The store never resends a stale
whole-document snapshot and never keeps a document history. A caller's
snapshot carries the revision it was derived from; if that revision is not the
store's adopted revision, the store re-reads and conflicts rather than letting
a first bar persist overwrite what the settings application already wrote.
The settings application starts on the control socket when the bar answers and
otherwise uses the file transport. A server-side rejection
(`ControlServerException`) stays on the socket; it flips to the file only after
the first `ControlSocketException`, including a save after the bar exits, and
the fallback is sticky for the session.

**Persistence.** The file transport keeps the current document plus one
last-good copy. A write takes an advisory lock on `settings.json.lock`, so its
read/check/rename is one critical section across transports and processes;
the lock file is retained, never deleted (deleting it would defeat exclusion).
Production waits for the lock asynchronously; widget tests opt into the sync
lock. A write snapshots the last document known to decode (`_lastGood`) into
`.prev` through a unique `.prev.tmp.<pid>.<time>` file and an atomic rename,
then writes the live document through a unique `.tmp.<pid>.<time>` file and
renames it into place. It never copies the possibly corrupt live file into
`.prev`.

A valid live document always wins, including a deliberate external rollback to
a lower revision. `.prev` and the in-memory last-good copy recover only when
the live document is missing, unreadable, or corrupt; between those two, the
newer revision wins. An unreadable candidate is skipped the same way as an
undecodable one. Normal bootstrap uses this recovery, seeds `.prev`-backed
documents instead of overwriting them, and reports an outputs parse error and
a settings parse error independently; `--check` still validates the live
document itself. A settings document that failed to load is never replaced by
editor defaults: the save re-reads and conflicts against the real revision.
This is current + last-good + one previous snapshot, not a history.

**Editing and close.** Same-frame edits compose onto the pending document in
the settings application, while the same field still collapses to its latest
value. Closing from the in-app close control flushes pending settings and
outputs, rebases edits made while a write was in flight, and drains until
nothing is pending (bounded at 3 s). A titlebar close or Alt+F4 reaches Dart
through `settingsCloseRequested`; the native delete handler holds the window
while Dart flushes and calls `settingsClose`, with a 5 s native fallback so a
dead isolate cannot make the window unclosable. A failed flush still closes.

**Keyboard and focus.** Every settings control is a focusable action target:
Tab traverses, Enter or Space activates buttons, chips, toggles, navigation
rows, and reset controls, and sliders step along their scale with the arrow
keys, clamped exactly like the semantics path. Focus rings use the accent;
selected chips and enabled toggles switch to a contrasting ring so the accent
fill cannot swallow it. The options inspector is modal to pointer input,
keyboard focus, and the semantics tree (a scrim, its own `FocusScope` and
traversal group, and a `BlockSemantics` barrier), closes on Escape or its close
control, and restores focus to the gear that opened it. A left or right strip
hides the clock date and seconds, so the inspector disables both toggles and
notes why. Switching sections resets the page scroll to the top. These are
window-local behavior; documents, revisions, and persistence are unchanged.

**Module availability.** The settings application probes hardware once and
refreshes when the probe's document inputs change. Disk availability means an
existing path, whether a mount directory or a file inside the mount; network
availability means a physical link or the pinned `network.interface`;
keyboard layout means an available backend with an active layout, matching
`KeyboardLayoutState.hasLayout`, with the running bar's control status
preferred over the process environment. A `disk.path` or `network.interface`
edit schedules one re-probe 250 ms after the preview, and a completed save
re-probes if the last answer still belongs to older inputs. A loader failure
keeps the last good answer, a stale loader answer is dropped, and a fresh
answer prunes an inspector whose enabled module became unavailable. A row
dropped from Disabled enables and moves only when released inside a real zone
(heading or card); a page-header or outside release leaves it disabled and in
place. Enabled-row drags still follow the nearest zone.

**Gaps.**

- A settings document with an invalid scalar type is an invalid document; if
  neither the live file nor `.prev` decodes and nothing is remembered, normal
  startup falls back to defaults; `--check` still fails it.

## Live reload

**Current.** A `dart:io` watcher on the config directory debounces 200 ms and
reloads through the bootstrap path. A watch stream that errors or closes is
replaced after 500 ms, doubling to a 5 s cap; dispose is terminal.
`ConfigWatcher.start` never throws: a directory-creation or watch failure
enters the same retry path, and dispose leaves no subscription, debounce, or
restart timer. An invalid file logs and keeps last-good state; the other
document from the same reload still applies, so a corrupt `settings.json` does
not postpone a valid `outputs.conf` change (or the reverse). The bar never
crashes over config.

- **Hot keys** (accent, module list/order, clock format, thresholds) rebuild
  providers. The settings application watches the same directory and reloads
  both settings and outputs, while an unsaved outputs preview owns the
  displays page until its save lands.
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

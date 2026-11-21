# Trickster suggestions

Agent-proposed, user-reviewed findings. If you see something the queue, the
constitution, or the code gets wrong — a missed Denial parallel, a performance
trap, a memory risk, a lifecycle miss, a config wart, a docs gap — propose it
here so the next session sees it. Standing rules belong in `AGENTS.md`, not
here.

Non-authoritative: entries inform decisions but bind nothing until the user
escalates them to `.llm/todo.md` (see `AGENTS.md` → Instruction precedence).
Nothing in this file authorizes performance work.

## Rules

- Entries must be **absolutely needed**: they prevent a future mistake,
  unblock queued work, or record a decision with its reason.
- One entry per issue. Keep it to five lines: what, where, why, action.
- Cite symbols and files, never source line numbers.
- Append after every change when a finding meets the bar; findings never live
  only in the transcript.
- Remove an entry in the same change that resolves it.
- At a phase boundary, walk every open entry with the user and settle it —
  keep, condense, move, escalate, or dismiss.

## Memory and release risk

- **Unused Lucide weight fonts ship.** The used subset is 5,828 B, but six
  unused variable-weight fonts total 3,160,400 B. JetBrains Mono adds 551,688 B
  for both weights. Audit the package asset set; remove weights the bar never
  selects without breaking dynamic glyph coverage; 4.0.3 is not smaller.

## Lifecycle and ownership

- **3.50 hide/show can leave a black strip.** `#196862`: after
  `gtk_widget_hide`/`show`, GTK replaces the toplevel `wl_surface` and the
  subsurface is not recreated. Trickster hides/shows strips for
  `outputs.conf=hidden` and overlays on map/unmap. Exercise both on 3.50.1;
  fix by destroy/recreate if it reproduces, never speculatively.

- **MPRIS controls are dropped while the worker respawns.** The proxy returns
  immediately when no command port exists, so a play/pause/next/previous
  pressed during the 1–30 s backoff is lost. Consider a bounded one-shot
  retry or disabling the controls while unavailable.

- **`pickImageFile` runs a nested GTK main loop.** `gtk_dialog_run` makes the
  settings process re-entrant while the chooser is open. Keep it modal and
  preview-free; move to `GtkFileChooserNative`/portal with a callback if
  flicker or double-open reports appear.

- **gtk-layer-shell 0.10 `respect_close` needs a reproduction.** Since 0.10.0
  compositor `closed` events are ignored unless `gtk_layer_set_respect_close`
  is set. Do not patch speculatively: reproduce a stale strip on output
  removal first, then guard the fix for older installed libraries.

## Performance and refresh

- **StatusNotifier offload is justified by measured frame-scale stalls.** One
  conforming 128² pixmap parse costs ~5.3 ms p50 on the UI isolate (256²
  ~21.8 ms, 512² ~90.5 ms, AOT), and 32×64² at 10 Hz takes 54% UI CPU. The
  pure-Dart D-Bus parse dominates; `dart:ui`/flutter_svg icon-file decoding is
  ~1.56 ms and stays on the UI isolate. The worker proxy is now the production
  default; the local service remains for tests and injected use. Only live
  tray verification remains before closing this entry.

## Correctness and verification

- **The settings window still opens at 980×720.** `gtk_window_set_default_size`
  requests a size larger than a 900×600 work area and there is no minimum size;
  the page now reflows at 900×600, but the initial toplevel does not. Size from
  the monitor work area or add a bounded minimum before smaller displays ship.

- **Keyboard availability refreshes only when the modules page opens.**
  `ModulesBloc` asks the bar once at creation; a Hyprland session that starts
  later leaves the row unavailable until the page is reopened. Refresh on a
  control-status change or expose a retry.

- **Equatable 3.0 still compares `runtimeType` at the top level;**
  single-state-per-bloc architecture makes cross-class collisions inert.

- **OpenCode's usage API is experimental.** The module reads
  `$XDG_STATE_HOME/opencode/service.json` and
  `/api/experimental/usage/limits`, both internal OpenCode surfaces that may
  move between releases. If the pill disappears after an upgrade, re-check that
  document and route first.

- **Second-display live checks are still deferred.** The grim accent fallback
  and per-display appearance merged without their two-output checks. When a
  second monitor is available, confirm swatches come from the screencopy
  capture and per-display accents apply.

- **A login-time bar can stick on its first frame.** Observed once at a session
  start that modeset HDMI-A-2 from 60 Hz to 165 Hz HDR: the strip held its
  launch frame while Dart timers stayed live; eight settled-compositor restarts
  did not reproduce it. Kill only the process and relaunch; capture frame
  timings if it recurs.

## Constitution alignment

These are claims in `AGENTS.md` that the current tree contradicts. They are
proposed amendments only; do not edit `AGENTS.md` without the user's explicit
sign-off.

- **UPower battery.** AGENTS lists battery as UPower in the module set, the
  D-Bus services, and the port list. Current code is a 5 s sysfs sampler with
  no UPower client. Either amend the constitution or queue the UPower port.

- **Per-output frame scheduling.** AGENTS says frame scheduling follows the
  output that hosts the surface. The GTK embedder has one 60 Hz fallback for
  the whole engine and no per-output vsync. Amend the claim to match the
  process-wide frame path.

- **Spring motion.** AGENTS describes a "spring entrance" and "motion springs".
  Current motion is 220 ms `easeOutCubic` with 12 px travel and a 60 ms
  stagger, plus the workspace lens timings; there is no spring simulation.
  Amend the wording.

- **Blanket package stripping.** AGENTS says release packages are stripped and
  that `options=('!strip')` is not the default. Both PKGBUILDs set
  `options=('!strip' '!debug')` and strip only the C++ runner; Dart AOT payloads
  must not be stripped. Amend the policy, not the package.

- **Overlay count.** AGENTS says one transient overlay surface while a tray
  menu is open. The bar creates independent fullscreen overlays for menus,
  tooltips, the calendar, and the volume slider. Amend the surface description.

- **`LayershellWindowController` does not exist.** AGENTS names it as a
  disposable resource. The tree uses `LayerShell`; there is no such controller
  class. Replace the name with the real native/Dart owners or drop it.

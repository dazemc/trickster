# Trickster suggestions

Agent-proposed, user-reviewed suggestions. If you see something the queue,
the constitution, or the code gets wrong — a missed Denial parallel, a
performance trap, a config wart, a docs gap — propose it here so the next
session sees it. Standing rules and instructions belong in `AGENTS.md`, not
here.

Non-authoritative: entries inform decisions but bind nothing until the user
escalates them to `.llm/todo.md` (see `AGENTS.md` → Instruction precedence).

## Rules

- Entries must be **absolutely needed**: they prevent a future mistake,
  unblock queued work, or record a decision with its reason. Brainstorming,
  nice-to-haves, and restatements of `.llm/todo.md` do not belong here.
- One entry per issue. Keep it to five lines: what, where, why, and what
  to do about it.
- Append after every change: review the touched code for misses and add
  entries that meet the bar; findings never live only in the transcript.
- Remove an entry in the same change that resolves it — same discipline as
  `.llm/todo.md`.
- After finishing any `.llm/todo.md` step, re-read this file and update it, but
  only if something meets the bar above. No obligatory edits. Silence is a
  valid review outcome.
- At a phase boundary, walk every open entry with the user and settle its
  decision — keep, condense, move, escalate, or dismiss — before the next
  phase starts.

## Open suggestions

- **Second-display live checks.** The grim fallback (18.8) and per-display
  appearance (14.12) merged without their two-output live checks, and the
  user deferred them again (no second monitor on hand). When one is
  connected, select it on the appearance page and confirm its swatches come
  from the screencopy capture and its accent overrides apply; a failure
  becomes a queued step.

- **`pickImageFile` runs a nested GTK main loop.** `my_application.cc` opens
  the chooser with `gtk_dialog_run`, so the settings process is re-entrant
  while it is open. Keep it modal and preview-free; if flicker or double-open
  reports appear, move to `GtkFileChooserNative`/portal with a callback.

- **OpenCode's usage API is experimental.** The module reads
  `$XDG_STATE_HOME/opencode/service.json` and
  `/api/experimental/usage/limits`, both internal OpenCode surfaces that may
  move between releases. If the pill silently disappears after an OpenCode
  upgrade, re-check that document and route first; the parser lives in
  `lib/src/services/opencode.dart`.

- **The `l10n.yaml` header is load-bearing.** Flutter 3.50's `gen-l10n` still
  emits deprecated `GlobalMaterialLocalizations` from `flutter_localizations`.
  The quoted `header: "// ignore_for_file: deprecated_member_use"` suppresses
  those infos in generated files; removing it (or regenerating without it)
  breaks `flutter analyze`. Keep the quote: an unquoted value is invalid YAML.

- **A bar started at login can stick on its first frame.** Observed at a
  22:49 session start that modeset HDMI-A-2 from 60 Hz to 165 Hz HDR: the
  strip held its launch frame for 35 minutes while Dart timers stayed live;
  eight settled-compositor restarts did not reproduce it. Kill only the
  process and relaunch to recover; capture frame timings if it recurs.

- **`ext-workspace-v1` deferred: no occupied bit.** The staging protocol
  (`ext_workspace_manager_v1` v1, live on this host) gives event-driven
  workspaces to niri, Hyprland and COSMIC, but it has no `occupied` state while
  `lib/src/bar/workspaces.dart` renders occupied/empty pips from it. Switching
  Hyprland off the JSON IPC backend would regress the rail. Keep the IPC
  backends; revisit only if the protocol gains occupancy or the pip model
  changes.

- **gtk-layer-shell 0.10 `respect_close` needs a reproduction.** Since 0.10.0
  compositor `closed` events are ignored unless `gtk_layer_set_respect_close`
  is set. Do not patch speculatively: reproduce a stale strip on output
  removal first, then guard the fix for older installed libraries.

- **Battery sampling still uses synchronous sysfs I/O.** `lib/src/services/
  battery.dart:32-74` runs `listSync`/`readAsStringSync` on the UI isolate
  every 5 s and emits unconditionally. Make UPower `PropertiesChanged` the
  primary source and move the sysfs fallback off the frame isolate.

- **D-Bus parsing runs on the UI isolate.** `status_notifier.dart:207,263` and
  `mpris.dart:185` create session clients on the UI isolate; signal coalescing
  bounds frequency but not parse cost. Tray icon bursts can drop frames; move
  proxies to the existing `background_worker.dart` pattern.

- **Native connector lookup repeats Wayland roundtrips.**
  `linux/runner/my_application.cc:199-234` creates a fresh `wl_registry` and
  performs two `wl_display_roundtrip` calls per lookup (outputs, surface
  create, surface setup). Cache the connector per `GdkMonitor` and invalidate
  in `monitor_removed_cb`.

- **Blur rect generation is per-frame work.** `lib/src/bar/blur_region.dart:
  175-189` builds roughly one `Rect` per pixel row per pill, then compares
  them all. Cache by `(bounds, radius)` and flush only when dirty.

- **Tray pixmap equality scans full RGBA buffers.**
  `lib/src/services/status_notifier.dart:90-99` and `lib/src/bar/tray.dart:
  350-355` compare whole buffers on every update. Add a monotonic revision or
  identity check first and compare bytes only as a fallback.

- **Niri emits duplicate workspace states.** `lib/src/services/workspaces.dart:
  957-993` adds state on every matching line without a `listEquals` dedup,
  unlike Sway. Add the same last-snapshot guard.

- **Stopped modules cancel subscriptions but keep services alive.**
  `cpu_bloc.dart:51-54`, `gpu_bloc.dart:51-54`, `battery_bloc.dart:53-59`,
  `media_bloc.dart:60-66`, `tray_bloc.dart:84-87` and `workspaces_bloc.dart:
  73-79` never dispose the underlying sampler. No production path dispatches
  those events yet; add disposal before enabling runtime module toggles.

- **Band worker exit leaves the monitor capture running.** `bands.dart`'s
  exit listener calls `_teardown()` and rests the bars but never cancels
  `_frames` or stops `_capture`, so PipeWire keeps delivering frames until the
  next stop. Cancel the frame subscription and stop the capture in that path.

- **The bar's post-frame startup can outlive dispose.** `lib/src/app.dart:113-134`
  registers the config watcher and control server in a post-frame callback
  with no mounted guard; if the app is disposed before the first frame,
  `dispose()` sees both fields null and the callback later creates orphan
  instances with live timers. Guard the callback with `if (!mounted) return;`
  or construct both before it.

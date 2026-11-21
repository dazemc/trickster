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

- **A long preview drag grows `DebouncedSaver._changes` without bound.** Every
  `apply` appends a closure and restarts the 300 ms timer; a slider held for
  minutes retains one change per frame and replays them all in
  `_composedPending`/`rebase`. Collapse same-field changes or cap the batch.

## Lifecycle and ownership

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

- **Settings launches have no single-instance guard and fail silently.**
  `BarMenuBloc._onSettingsSelected` ignores the `false` from
  `launchTricksterSettings`, and every selection starts another detached
  process, so two windows can race the revision line with no feedback on
  failure. Reuse the running window and surface a failed start.

- **The settings output list only loads at startup.**
  `SettingsAppBloc._onLoad` reads `_layerShell.outputs()` once and no resume,
  focus, or metrics path refreshes `availableOutputs`; a monitor plugged in
  while the window is open gets no displays row or appearance chip until
  reopen. Probe on focus/resume or expose a refresh.

- **Grim captures have no timeout.** `GrimSampler.available`/`sample` await
  `Process.run` with no deadline, so a hung `grim` keeps
  `WallpaperAccentBloc._localSampling` true and blocks every later sample until
  the child exits. Bound the process and kill it on timeout.

- **The wallpaper cache watcher never resubscribes.**
  `WallpaperAccentBloc._startWatch` installs `onError: (_) {}` and leaves
  `_watch` non-null, so a stream error or close stops cache refreshes until the
  source is toggled. Null the subscription and retry with backoff like
  `ConfigWatcher`.

- **Overlapping disruptive reloads can recreate surfaces concurrently.**
  `_apply` starts `unawaited(_recreateSurfaces(loaded))` with no in-flight
  guard, so two quick edge/thickness/layer reloads can interleave destroy and
  configure and map the same strip twice. Serialize or coalesce the recreate
  path like `_reconcileOutputs`.

## Performance and refresh

- **Enabled-but-unavailable modules still start their blocs and samplers.**
  `BarSettings` defaults to `knownModules`, and `ModuleScope` gates providers
  only on `settings.includes`, so battery, GPU, keyboard, and backlight samplers
  run on machines the settings page marks unavailable. Gate providers on the
  same predicates or seed only available modules.

- **A settings-app save reloads both documents.** The watcher always adds
  `SettingsAppDocumentChanged` and `SettingsAppOutputsChanged`, so each save
  re-reads the other document over the socket; with a settings draft open, an
  outputs-only event also raises the false "settings changed elsewhere" banner.
  Dispatch by the event path.

- **`ModuleAvailability` still has no value equality.**
  `ModulesState.unavailable` compares lists element-by-element, so a probe that
  returns the same answers rebuilds the modules page; `LayerOutput` already
  implements `==`/`hashCode` for the same reason. Add both to
  `ModuleAvailability`.

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

- **Keyboard availability refreshes on config edits, not on a late backend.**
  `ModulesBloc` now re-probes after `disk.path`/`network.interface` edits and
  saves, but a bar-side keyboard backend that appears after the page opens
  still leaves the row unavailable until the page is reopened. Refresh on a
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

- **GPU is the only module with a render predicate but no availability row.**
  `probeModuleAvailability` covers `vram` via `hasGpuMemorySource`, while the
  bar hides `gpu` unless some `GpuLoad.usage != null`; RAM/CPU null samples are
  transient reads, not hardware rows. Add a usage-source predicate and reason.

- **The outputs watcher cannot match another symlink spelling.**
  `normalizeConfigPath` deliberately leaves links unresolved, so a custom
  outputs parent reported under a different spelling never equals
  `configDocumentFilter`'s live path; file edits and the file fallback miss
  reloads (socket saves still call `reload()`). Compare canonical parents.

- **`seedUserConfig` does not create a custom outputs parent.** It creates only
  `ConfigPaths.directory`; when an override's parent is missing, the seed write
  logs and the bar runs defaults until a watcher or settings save creates it.
  Create the outputs parent before seeding.

- **Malformed media and OpenCode scalars silently default.**
  `MediaOptions.fromJson` replaces a non-numeric `bars`/`volume_step` with its
  default and `OpencodeOptions.fromJson` does the same for a non-bool
  `show_cost`, while sibling options reject wrong types. Throw
  `FormatException` so bootstrap and `--check` agree.

- **Settings-app state and outputs reads hide malformed input.**
  `SettingsAppState.fromJson` hard-casts `error`/`outputs_error`, throwing on a
  non-string, while `FileOutputsTransport.read` returns default placement when
  live and `.prev` are unusable without setting `outputsError`. Decode strings
  defensively and surface the outputs parse error.

- **The control server writes to a client that may be gone.**
  `ControlServer._onConnection` awaits the handler and then writes/flushes with
  no guard; a client that hit `controlRequest`'s 2 s timeout has closed, so the
  reply write can throw an unhandled socket error. Guard the write and drain.

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

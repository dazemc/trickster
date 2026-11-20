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

- **`PipeWireCapture.dispose()` does not stop the native stream.** It frees the
  Dart wrapper while the native capture keeps running. Call the native stop
  before free, and test a media-module teardown.

## Lifecycle and ownership

- **Overlay surfaces survive output removal and app dispose.** The overlay
  constructor receives a monitor but never assigns `surface->monitor`, so
  `monitor_removed_cb` cannot destroy it. The tray/calendar/volume/tooltip
  blocs have no `close()` surface teardown, and several full-monitor overlays
  can stack. Track overlays per output and close them from the owning bloc.

- **3.50 hide/show can leave a black strip.** `#196862`: after
  `gtk_widget_hide`/`show`, GTK replaces the toplevel `wl_surface` and the
  subsurface is not recreated. Trickster hides/shows strips for
  `outputs.conf=hidden` and overlays on map/unmap. Exercise both on 3.50.1;
  fix by destroy/recreate if it reproduces, never speculatively.

- **The bar's post-frame startup can outlive dispose.** `app.dart` registers
  the config watcher and control server in a post-frame callback with no
  mounted guard; a dispose before the first frame leaves orphan instances with
  live timers. Guard the callback or construct both before it.

- **Stopped modules cancel subscriptions but keep services alive.**
  `CpuStopped`, `GpuStopped`, `BatteryStopped`, `MediaStopped`, `TrayStopped`,
  and `WorkspacesStopped` do not dispose the underlying sampler/service, while
  `close()` does. No production path emits `Stopped` yet; make the two paths
  equivalent before enabling runtime module toggles.

- **The band worker exit path leaves capture running.** `bands.dart` rests the
  bars on worker exit but does not cancel `_frames` or stop `_capture`, and
  `VisualizerBloc` stays active. Cancel the frame subscription, stop the
  capture, and emit an inactive visualizer state.

- **`pickImageFile` runs a nested GTK main loop.** `gtk_dialog_run` makes the
  settings process re-entrant while the chooser is open. Keep it modal and
  preview-free; move to `GtkFileChooserNative`/portal with a callback if
  flicker or double-open reports appear.

- **gtk-layer-shell 0.10 `respect_close` needs a reproduction.** Since 0.10.0
  compositor `closed` events are ignored unless `gtk_layer_set_respect_close`
  is set. Do not patch speculatively: reproduce a stale strip on output
  removal first, then guard the fix for older installed libraries.

- **Settings saves do not fall back to the file after the bar exits.** The
  settings application chooses its transport at startup; if the bar exits
  while the window is open, later saves fail. Retry the file path and keep the
  same revision line.

## Performance and refresh

- **Blur region generation is per-flush work.** `blur_region.dart` builds one
  `Rect` per pixel row per pill, then compares the whole list. Cache by
  `(bounds, radius)` and flush only when dirty; blur is not active on the
  current host, so this is latent but becomes visible on a blur-capable host.

- **Tray pixmap equality scans full RGBA buffers.** `SystemTrayIconPixmap.==`
  and `_RawTrayIcon.didUpdateWidget` compare whole buffers on every update.
  Add a monotonic revision or identity check first and compare bytes only as a
  fallback.

- **Native connector lookup repeats Wayland roundtrips.** Every lookup creates
  a fresh `wl_registry` and performs two `wl_display_roundtrip` calls. Cache the
  connector per `GdkMonitor` and invalidate in `monitor_removed_cb`.

- **niri emits duplicate workspace states.** Its handler adds a snapshot for
  every matching line without the `listEquals` guard Sway and Hyprland use.
  Add the last-snapshot guard before emitting.

- **D-Bus parsing runs on the UI isolate.** StatusNotifier and MPRIS create
  session clients on the UI isolate; signal coalescing bounds frequency, not
  parse cost. Move proxy work to the existing `background_worker.dart` pattern.

- **A settings-only reload enumerates outputs.** `_apply` calls
  `_reconcileOutputs` for every settings change, which calls native `outputs()`
  even when only a visual option changed. Skip the enumeration unless the
  output set or strip geometry changed.

- **`BackgroundWorker.invoke` has no per-request timeout.** A wedged NVML call
  can stall GPU sampling forever. Add a request timeout that tears down and
  recreates the worker, with a test for the wedged path.

- **Control listener errors are swallowed.** `ControlServer` has no retry or
  rebind when the listener fails. Surface the error, retry with a bounded
  backoff, and do not leave a dead socket path behind.

- **Blur and volume globals are not rebound on removal.** The blur manager
  global removal leaves the native effect object in place; volume global
  removal leaves bound proxies. Rebind both on a new global and release the
  stale objects.

- **D-Bus transport recovery is all-or-nothing.** When the session bus drops,
  the services rebuild the whole client; a re-listen after a match-rule
  refcount mismatch can be a silent no-op. Add a reconnect path that
  re-establishes match rules and verifies the subscription, not just an
  `onError` refresh.

- **Reduced-motion coverage is partial.** The workspace lens/switch and the
  visualizer honor `MediaQuery.maybeDisableAnimationsOf`; the pill entrance and
  other transitions do not. Audit every timed transition before claiming
  accessibility parity.

## Idle and sampling

- **Battery sampling still uses synchronous sysfs I/O.** `battery.dart` runs
  `listSync`/`readAsStringSync` on the UI isolate every 5 s and emits
  unconditionally. It is not UPower. Move the read off the frame isolate, gate
  it on seat idle, and make UPower `PropertiesChanged` the primary source when
  that port lands.

- **Idle pause covers CPU/GPU only.** Battery's 5 s sampler and OpenCode's 60 s
  poll still run while the seat idles; MPRIS keeps its deliberate 60 s recovery
  poll. Extend the `SeatIdleBloc` gate where idle cost matters. The observer
  binds only the first seat; multi-seat compositors need one notification per
  seat.

## Correctness and verification

- **Equatable 3.0 no longer compares `runtimeType`.** Distinct state classes
  that declare the same props now compare equal, so bloc dedup can swallow a
  transition. Audit every bloc state `==` once; do not downgrade for this.

- **`TRICKSTER_LOG` is parsed but unused.** `SessionConfig.log` never reaches a
  logger. Either wire it to the observer/log filter or remove it from the
  documented contract.

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

# Trickster performance, refresh rate, and memory

Domain knowledge subordinate to `AGENTS.md` and `.llm/workflow.md` (see
`AGENTS.md` → Instruction precedence); on a conflict the higher document wins
and this file is corrected.

Status words: **Current** is verified in the tree; **Gap** is a known
divergence tracked in `.llm/suggestions.md`; **Aspiration** is intent, never
shipped behavior.

## The frame is process-wide

**Current.** The bar is one process with one Flutter engine, one UI isolate,
and one raster thread. The engine hosts the bootstrap view, one strip view per
hosted output, and independent fullscreen overlay views for tray menus,
tooltips, the calendar, and the volume slider. The settings application is a
separate process with its own engine.

Frame cost is therefore process-wide and additive, not per-output:

- a 30 Hz visualizer on one strip spends part of the same raster budget as
  every other strip;
- a 220 ms entrance on one output schedules frames for the whole engine;
- a mapped overlay adds a fullscreen surface to compositing even when its
  visible content is small;
- there is no per-output frame scheduler, no per-output vsync, and no way for
  one output to run at a different cadence than another.

The 60 Hz ceiling below is a property of the whole process, not of a monitor.

## Refresh ceiling and provenance

**Current.** Flutter 3.50.1's Linux GTK embedder has no vsync callback. The
engine ticks on a fixed 60 Hz `VsyncWaiterFallback` and never reads the
output's refresh rate. The current host is 3840×2160 at 164.991 Hz, scale 2,
and the bar still presents at the fallback cadence. There is no per-output
frame scheduling, no >60 fps claim, no VRR, and no presentation feedback.

Upstream tracking: `flutter/flutter#191245`, `#183703`, and `#196776`. The GTK
redraw fix `#195287` is not in 3.50.1. Do not fork, patch, or pin a patched
engine; revisit when the work reaches a stable release. App-side rebuild and
raster cost is still ours to fix.

**Aspiration.** A future Flutter stable may expose compositor frame timing.
Until then, a motion that "looks 165 Hz" is a 60 Hz animation with less work,
not a faster clock.

## Cost model and recorded measurement

The frame budget is 16.7 ms at 60 Hz. The engine cadence dominates; the app
must still keep build and raster work well below the budget so a busy output
does not starve the others.

Last recorded app-side measurement (2026-09, profile build, 4K@60 output at
scale 2, accent-wheel drag, `SchedulerBinding.addTimingsCallback` plus
temporary rebuild and pointer counters):

- build average 0.7–1.1 ms, p95 ≤1.7 ms;
- raster average ~1 ms, p95 ≤1.9 ms;
- `vsyncOverhead` average 2.3–3.0 ms against 16.7 ms;
- after the drag fix, the shell rebuilt twice and the nav once over ~250
  frames, while the active page and wheel rebuilt about once per frame.

This is a regression reference, not a current-host measurement. Re-measure
before quoting it for a new Flutter or output.

## Rebuild algebra

**Current.** The strip paints nothing. Every pill sits inside its own
`RepaintBoundary`; module state is read with `BlocBuilder` or `select`; a
clock tick rebuilds only the clock pill; the visualizer rebuilds only its
equalizer mark. A pointer move must not rebuild the shell or every pill.

The clock is minute-aligned by default. It runs at 1 Hz only while the seconds
field is painted, then returns to minute alignment. The `ClockBloc` is shared,
but only the clock pill listens to its state.

The visualizer is active only while a player is playing **and** the pill paints
the equalizer. Its native PipeWire pump delivers every 33 ms (~30 Hz), the FFT
runs on a widget-free worker isolate, and the mark repaints inside its own
boundary. When either condition clears, the capture and isolate are stopped.
**Gap:** on worker exit the analyzer rests the bars but leaves the capture and
frame subscription running; see `suggestions.md`.

Per-view overlay keys keep a menu or tooltip on one output from rebuilding the
strips on another.

**Current cost caveats:**

- the strip watches the whole `SettingsBloc` and `WallpaperAccentBloc`, so a
  settings preview or accent change rebuilds the strip even when only one
  module option changed;
- the entrance `Opacity`/`Transform` sits outside the pill's
  `RepaintBoundary`; the cached pill is composited rather than repainted, but
  the animation still schedules frames for its full duration;
- a non-disruptive reload still calls native `outputs()`, a Wayland
  enumeration, even when only a visual option changed.

## Motion inventory

**Current.** Motion is finite and one-shot. There are no spring simulations
and no repeating tickers.

| Motion | Timing | Behavior |
| --- | --- | --- |
| Pill entrance | 220 ms `easeOutCubic`, 12 px travel | 60 ms stagger per pill index; once per pill creation |
| Workspace lens takeoff | 72 ms | Only on workspace change |
| Workspace lens travel | 168 ms | Continues from the current deformation |
| Workspace lens settle | 80 ms | Returns to rest |
| Clock | minute-aligned | 1 Hz only while seconds are painted |
| Equalizer | 33 ms native pump | Only playing and visible |

The old "spring entrance" and "motion springs" language is **not current**.
The spring references are a constitution correction in `suggestions.md`.

Reduced motion currently reaches the workspace lens/switch and the media
visualizer through `MediaQuery.maybeDisableAnimationsOf`. The pill entrance and
other transitions do not yet honor it. **Gap.**

## Backdrop blur

**Current.** Native blur is opt-in twice: the host must advertise
`ext-background-effect-v1` and the manager must report the blur capability.
A manager global alone is not enough. The effect is set per strip as a region
of pill rectangles; each stadium card is approximated with one-pixel
horizontal strips so the region follows the rounded ends. The fallback is a
translucent gradient at alpha .92/.88 with no resting border — not a
fill-plus-border card.

The Dart side registers each pill's live bounds with a `BlurRegionController`.
Flushes run after the frame that moved a card, compare the new list with
`listEquals`, and resend only on change or when a scroll translates a cached
layer. Native caches the last region so a remap can re-apply it, creates the
effect object once, and commits the surface so region-only changes apply
without a new frame.

Overlay surfaces never take the native effect; an effect on a hidden overlay
black-screens it. The current host does not advertise the blur capability, so
the fallback path is the active one.

**Gap.** Region generation still rebuilds the scanline rows for every pill on
each flush. Cache by `(bounds, radius)` and flush only when dirty.

## Idle and sampling cadence

Seat idle is observed through `ext-idle-notify-v1` on the first seat with a
60 s timeout. The notification is inhibitor-aware and purely observational: it
reads no input devices, installs no inhibitor, and rebinds when the compositor
removes and later re-advertises the seat or notifier. Without the protocol,
samplers keep their normal cadence. Multi-seat compositors are a gap.

| Service | Cadence | While seat idle |
| --- | --- | --- |
| CPU | 1 Hz `/proc/stat` | Paused; one 100 ms prime sample on resume; 45-sample history; reused buffer |
| GPU | 1 Hz sysfs/NVML | Paused; in-flight generation dropped; 45-sample history |
| Battery | 5 s sysfs | Still polls; synchronous I/O; **gap** |
| OpenCode | 60 s HTTP | Still polls; **gap** |
| MPRIS | D-Bus signals + 60 s recovery | Recovery poll is deliberate; 16-player cap |
| StatusNotifier | D-Bus signals; 45 ms coalesce | Event-driven |
| Workspaces | Sway/Hyprland/niri events | Event-driven; Hyprland 32 ms debounce |
| Clock | minute-aligned / 1 Hz | Continues |
| Wallpaper accent | wall-clock cache change, 300 ms debounce | Only when source is wallpaper |
| Visualizer | 33 ms PipeWire pump | Only playing and visible |
| Sink volume | PipeWire watch | While the media module is configured |

Rules that follow from the table:

- A disabled module owns zero blocs, subscriptions, timers, and D-Bus names.
- Prefer D-Bus signals and compositor IPC events over polling.
- `/proc` and sysfs samples are bounded and reuse buffers; do not allocate a
  new string per sample when a reused buffer will do.
- The visualizer capture and FFT isolate exist only while playing and visible.
- The sink volume is watched over one PipeWire connection, event-driven, never
  through `wpctl` or a poll.
- Battery is **not** UPower today. It is a 5 s synchronous sysfs sampler. The
  UPower migration is an open port/performance gap.

## Event-driven service contracts

**Hyprland IPC.** Commands use `.socket.sock`; events use `.socket2.sock`.
A command connection is dialed and written in one turn. Never hold an idle
`.socket.sock` connection: the compositor blocks in `poll()` waiting for the
command, which can stall the initial layer-shell configure and tear down the
first surface. Every request is a one-shot connection with a bounded read, a
timeout, and a close. A refused or reset connection retries once on a fresh
connection after a settle delay; event sockets reconnect with capped backoff.
Socket work runs on worker isolates. One workspace switch emits several
matching lines: debounce the burst (32 ms), coalesce events during a refresh
into one follow-up query, and dedup identical snapshots before emitting.

**Startup ordering correction.** The engine starts on the bootstrap
`fl_view_new(project)` view. Strips are created and mapped in the same GTK
activate turn, before Dart IPC begins. The earlier claim that the engine waits
for the first strip's initial configure was wrong. The one-turn write rule is
still required because a silent command connection can block the compositor.

**StatusNotifier and MPRIS.** D-Bus signals are primary; coalescing bounds
signal bursts, not parse cost. SNI caps 64 items, 256 icon paths, 64 decoded
icons, 512 px input, 64 px output, and 8 MiB per icon file. MPRIS caps 16
players and keeps a 60 s recovery refresh. Both services currently open their
D-Bus clients on the UI isolate; moving proxy work to the existing
`background_worker.dart` pattern is a performance gap.

**Workspaces.** Sway/i3 IPC, Hyprland sockets, and niri's event stream are
event-driven. niri lacks the Sway/Hyprland snapshot dedup; a duplicated
`WorkspacesChanged` line can repaint the rail. 1 MiB reply caps and 32 ms
Hyprland debounce bound the rest.

## Startup and shutdown cost

**Current startup order.** Native installs the method channel and idle
observer, then shows the bootstrap view; the engine starts there. Strips and
overlays use `fl_view_new_for_engine`. Each monitor's connector lookup creates
a fresh `wl_registry` and performs two `wl_display_roundtrip` calls; there is
no per-`GdkMonitor` connector cache. Dart probes idle once with a 1 s timeout
before `runWidget`. The entrance animation starts with the first pills.

`--check` is a cold-process preflight; a warm run measured about 372 ms. It is
not a startup benchmark for the bar.

Flutter 3.50.1 emits a cursor-theme warning and `Timed out waiting for
subsurface frame` lines at startup. They are upstream and benign; the 2×2
view is the empty bootstrap. The timeout costs about 100 ms per view and can
also mark a real resize stall, so never suppress the message. Re-check on the
next stable.

**Shutdown.** Dispose every watcher, control server, overlay bloc, timer,
subscription, D-Bus client, IPC socket, and native surface in the scope that
created it. Known gaps:

- the app's post-frame startup callback has no mounted guard, so a dispose
  before the first frame can leave an orphan watcher and control server;
- overlay surfaces have no output-removal teardown (see architecture);
- `PipeWireCapture.dispose()` does not stop the native stream;
- background worker shutdown is generation-safe, but `invoke` has no
  per-request timeout;
- control listener errors are swallowed without a retry.

Do not publish a shutdown RSS or latency budget from a single run.

## Memory and assets

**Current.** Resident size is process-wide. The settings process adds a second
engine only while open. Release builds are AOT; debug/profile engine artifacts
must not ship.

Bundle observations (current release):

- bundle ~28.4 MiB;
- `libapp.so` ~7.46 MB;
- engine ~17.45 MB;
- JetBrains Mono Medium + Bold 551,688 B;
- used Lucide subset 5,828 B, but six unused variable-weight fonts total
  3,160,400 B. **Gap.**

Caps:

- tray: 64 items, 64 decoded icons, 256 paths, 8 MiB source file, 512 px input
  dimension, 64 px output dimension;
- pip artwork: 16 entries, 8 MiB, 14 px;
- CPU/GPU: 45 history samples each;
- settings: current + last-good + `.prev`, no history;
- OpenCode: 60 s poll, 1 MiB response cap;
- MPRIS: 16 players;
- workspaces: 1 MiB reply cap, 32 ms Hyprland debounce;
- control socket: 2 s client timeout;
- background worker: 10 s startup timeout.

**Gap — wallpaper accent.** `_samplePath` reads the whole file and
`extractWallpaperAccents` constrains only width. A 269 MB 3840×2160 GIF has
been observed in the wild, and a VmHWM of ~1.64 GiB was observed on this host.
The wallpaper path is the leading suspicion, not a proven cause. Cap source
bytes and both dimensions, decode only the first frame, and test with a large
animated file before calling this closed. This is the highest memory risk in
the tree.

**Gap — tray decode.** The icon-file path constrains only
`targetWidth: 24`. A 1×N image can decode very tall before the >64 output
check rejects it; clamp `targetHeight` from the descriptor. Arbitrary
non-pixmap values returned by `GetAllProperties` are still retained.

**Observation, not a budget.** One runtime snapshot measured ~162 MB RSS,
~93 MB PSS, and 313 MB swap. VmHWM reached ~1.64 GiB, which is not a baseline
and must not be published as one. Re-measure after the wallpaper caps with a
fixed scenario (5 min idle, one wallpaper change, two overlay cycles) and
record the scenario with the number.

**Current package policy.** `options=('!strip' '!debug')` is deliberate in the
Arch PKGBUILDs. Dart AOT payloads, including `tricksterctl`, degrade or break
under `strip`; only the C++ runner is stripped explicitly. The blanket claim
that "packages are stripped" is false.

No previous frames, screenshot bitmaps, or offscreen wallpaper copies are
kept unless a measured accent sampler is enabled, and then only a downscaled
working buffer freed after the accent is committed.

## Logging

Release logs only state changes and errors. Debug/profile builds trace every
bloc event, transition, error, and lifecycle through `TricksterObserver`. No
per-frame or per-sample logging. `TRICKSTER_LOG` is parsed into
`SessionConfig` but never applied to a logger; that is a gap, not a working
filter.

## Measurement protocol

Before changing a performance path, record the baseline; after, repeat the
same scenario and keep the numbers with their provenance.

- Use a profile build for frame timings, a release build for live behavior.
- Record Flutter version, output resolution, scale, refresh rate, scenario,
  and whether blur was active.
- Use `SchedulerBinding.addTimingsCallback` for build/raster/vsync; use
  temporary counters only to prove rebuild scope.
- Measure idle CPU over at least 60 s with no pointer or keyboard input, and
  confirm no frames are scheduled when nothing is animating.
- Measure RSS/PSS with `/proc/<pid>/status` or `ps -o rss=`; state the
  scenario and duration. Never turn one snapshot into a budget.
- Remove every temporary counter and log before committing.
- Hand visual verdicts to the user with exact run-and-look commands; never
  substitute screenshots, and never force X11.

## Claims ledger

| Claim | Status | Evidence |
| --- | --- | --- |
| One bar process, engine, UI isolate, raster thread | Current | Native runner; single `fl_view_new(project)` bootstrap |
| Multiple FlViews share one frame budget | Current | Bootstrap + per-output strips + overlays |
| Settings is a separate process/engine | Current | `--settings` path |
| 60 Hz fixed engine fallback, no output refresh read | Current | Flutter 3.50.1 GTK embedder; upstream refs |
| No per-output scheduling, VRR, or >60 fps | Current | No native vsync/presentation path |
| 220/60 ms entrance, 72/168/80 ms lens, no springs | Current | Motion constants and controllers |
| Clock only rebuilds its pill | Current | Shared `ClockBloc`, pill-local builder |
| Visualizer 30 Hz only playing+visible | Current | 33 ms pump, FFT isolate, visibility gate |
| Worker-exit capture teardown | Gap | Analyzer rests bars but leaves capture/frames |
| CPU/GPU pause on seat idle | Current | `SeatIdleBloc` + samplers |
| Battery 5 s sysfs, not UPower | Current | `battery.dart` |
| Battery/OpenCode idle gating | Gap | No idle gate |
| Blur capability-gated, per-pill region | Current | Runner + `BlurRegionController`; not active on host |
| Blur region cache | Gap | Rebuilds scanline rows per flush |
| Tray 64/256/8 MiB caps | Current | `_StatusNotifierLimits` |
| Wallpaper source byte/dimension/frame caps | Gap | Whole-file read, width-only decode |
| Bundle ~28.4 MiB, fonts as measured | Current | Current release bundle |
| Unused Lucide weight fonts | Gap | Six variable fonts, 3,160,400 B |
| `!strip` with runner-only strip | Current | Arch PKGBUILDs |
| Memory budget | Unknown | One snapshot only; do not publish |

## Invariants and anti-patterns

- Never rebuild the strip for a clock tick, a pointer move, or one pill's
  data.
- Never start a disabled module's bloc, timer, subscription, or D-Bus name.
- Never add an interval poll where the platform can push.
- Never run a repeating ticker for decoration; motion is one-shot.
- Never copy the full screen, the wallpaper, or previous frames for blur.
- Never assume a monitor's refresh rate drives Flutter; it does not.
- Never claim >60 fps or per-output pacing on this embedder.
- Never strip a Dart AOT payload.
- Never cache an image without a byte, dimension, and entry cap.
- Never log per frame or per sample in release.
- Never call `outputs()` on a settings-only reload unless output placement
  actually changed.

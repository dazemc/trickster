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

Upstream watch: `flutter/flutter#191245`, `#183703`, and `#196776`. The GTK
parent-redraw fix `#195287` is merged on `master` and labeled for stable
cherry-pick, but it is not in 3.50.1; adopt it at the first stable that carries
it. `#196776` (display-refresh vsync) is an open, unmerged pull request. Do not
fork, patch, or pin a patched engine. App-side rebuild and raster cost is still
ours to fix.

The 3.50 subsurface renderer also carries open hide/show and resize risks:
`#196862` (black window after hide/show), `#196529` (startup freeze), and
`#196663` (second-resize deadlock). Exercise those paths on 3.50.1 before
trusting them; do not patch speculatively.

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

**StatusNotifier parse cost (2026-11, headless benchmark).** The real
`StatusNotifierService`/`DBusClient` path was driven by a fake-bus exporter
isolate under `flutter test`, one `PropertiesChanged` per update carrying
`Title`/`Status`/`IconPixmap`, with a 1 ms event-loop grid probe. The
in-process `DBusServer` in `dbus 0.8.1` corrupts signals above roughly 64 KiB
(a 262144-byte pixmap arrived as 65536, then the stream failed), so only 64²
loads ran end to end; 128² and larger were measured at the exact client parse
layer (`DBusReadBuffer` + `DBusPropertiesChangedSignal` + the product pixmap
decode) and cross-checked with an AOT `dart compile exe` of the same path.
AOT is within ~7% of the `flutter test` JIT numbers, so these are not
debug-build artifacts.

Per update, AOT: 64² (16 KiB wire) ≈1.1 ms; 128² (64 KiB) ≈5.3 ms p50, p95
5.9; 256² (256 KiB) ≈21.8 ms; 512² (1 MiB) ≈90.5 ms, p95 108. Cost is linear
at ~80–86 µs per KiB of pixmap bytes and is dominated by `dbus` materializing
one `DBusByte` per input byte; the pure-Dart downscale, premultiply, and digest
add only 0.08–0.14 ms. The `dart:ui` PNG decode (512² → 24²) is ~1.56 ms mean
with 0.69 ms event-loop p95, so it is not the bottleneck.

Sustained 8×64² at 10 Hz (1.3 MB/s) held p95 at 1.0 ms (max 7.4 ms, 15 samples
>4 ms in 5 s) at 15% UI CPU. 32×64² at 10 Hz (5.2 MB/s) took 54% UI CPU with
p99 5.1 ms (max 7.4 ms, 101 samples >4 ms) and grew process RSS by ~19 MB over
the window, allocator churn from parsed pixmap trees rather than a leak
signal. Each update is one synchronous burst: 128² already spends 32% of a
16.7 ms frame, 256² 1.3 frames, 512² 5.4 frames. Decision: move the D-Bus
backend and pixmap conversion to a worker isolate and keep the
`dart:ui`/flutter_svg icon-file decoder on the UI isolate. Deferral is
defensible only if the accepted pixmap domain were capped at 64² and a few Hz,
which it is not (512² input is accepted). Snapshot-driven tray rebuilds remain
a separate coalescing follow-up.

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

A terminal worker exit is generation-guarded: `BandAnalyzer` cancels the frame
subscription, tears down the worker ports/isolate, stops the capture, emits zero
levels, and signals failure once. Explicit `stop()` invalidates the generation
first, so it stays silent. `VisualizerBloc` drops the level subscription, emits
inactive/empty, and retries only while playing and visible with 1 s→30 s capped
exponential backoff; the delay resets only after real non-zero levels. Late
levels from an older generation are ignored. Dispose/close cancels the retry
timer and both subscriptions and waits for capture cleanup.

Per-view overlay keys keep a menu or tooltip on one output from rebuilding the
strips on another.

**Current cost caveats:**

- the strip watches the whole `SettingsBloc` and `WallpaperAccentBloc`, so a
  settings preview or accent change rebuilds the strip even when only one
  module option changed;
- the entrance `Opacity`/`Transform` sits outside the pill's
  `RepaintBoundary`; the cached pill is composited rather than repainted, but
  the animation still schedules frames for its full duration.

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

**Current.** Reduced motion reaches every timed transition through
`MediaQuery.maybeDisableAnimationsOf`. The entrance settles its controller and
schedules no stagger timer; the clock switcher, meter text style, media control
fill, and settings transitions take zero duration and land on their first
frame. The settings process installs `MediaQuery.fromView`, so the platform
flag reaches both processes. Widget tests pin the reduced path.

## Backdrop blur

**Current.** Native blur is opt-in twice: the host must advertise
`ext-background-effect-v1` and the manager must report the blur capability.
A manager global alone is not enough. The effect is set per strip as a region
of pill rectangles; each stadium card is approximated with one-pixel
horizontal strips so the region follows the rounded ends. The fallback is a
translucent gradient at alpha .92/.88 with no resting border — not a
fill-plus-border card.

The Dart side registers each pill's live bounds with a `BlurRegionController`.
Each provider caches its scanline rows by `(bounds, radius)`. `refresh(id)`
marks one provider dirty, no-arg `refresh()` marks all, and `resend()` marks all
for a remap/scroll while reusing every unchanged row set. Structural
register/unregister schedules a combined rebuild. A flush runs only when
something is dirty or structural, compares the final list with `listEquals`,
and sends only on change. Dispose clears providers/cache and ignores any
callback already in flight. Native caches the last region so a remap can
re-apply it, creates the effect object once, and commits the surface so
region-only changes apply without a new frame.

Overlay surfaces never take the native effect; an effect on a hidden overlay
black-screens it. Confirmed 2026-11-20 on the Hyprland 0.56 session:
`trickster --check` still reports `blur: not advertised (translucent fill)`,
so the fallback path is active. A compositor blur setting alone is not proof;
re-check after a compositor or Flutter update.

## Idle and sampling cadence

Seat idle is observed through one inhibitor-aware `ext-idle-notify-v1`
notification per advertised seat, each with a 60 s timeout. The observer reads
no input devices and installs no inhibitor. The aggregate is idle only when at
least one seat is bound and every seat with a live notification is idle; any
resume, seat removal/reset, or notifier loss falls back to false. Late seats
bind and a new notifier recreates every notification. Without the protocol,
samplers keep their normal cadence.

| Service | Cadence | While seat idle |
| --- | --- | --- |
| CPU | 1 Hz `/proc/stat` | Paused; one 100 ms prime sample on resume; 45-sample history; reused buffer |
| GPU | 1 Hz sysfs/NVML | Paused; in-flight generation dropped; 45-sample history |
| Battery | 5 s sysfs | Paused; one fresh sample on resume; async sysfs I/O; equal status deduplicated |
| OpenCode | 60 s HTTP | Paused; one fresh request on resume; in-flight generation dropped |
| MPRIS | Worker isolate; D-Bus signals + 60 s recovery | Recovery scan paused; signals and current state stay live; one scan on resume; 16-player cap |
| StatusNotifier | Worker isolate; UI icon decode; 45 ms coalesce | Worker starts with the configured tray module; event-driven |
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
- Battery is **not** UPower today. It is a 5 s asynchronous sysfs sampler,
  paused with the seat, with overlapping/post-pause reads generation-guarded
  and equal status deduplicated; the UPower migration is an open
  port/performance gap.
- MPRIS keeps its D-Bus signal subscriptions and selected player in its worker
  isolate while the seat is idle; only the 60 s recovery scan stops, and
  resume runs one scan before restoring the cadence.

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
icons, 512 px D-Bus pixmap input, 64 px output, 8 MiB per icon file, 4096 px
raster file dimension, and 4,194,304 raster file pixels. Raster decode targets
clamp both axes to a 24 px longest side; the SVG path stays vector-based. MPRIS
caps 16 players and keeps a 60 s recovery refresh, paused with the seat while
signals stay live. MPRIS parsing, discovery, and method calls run in its worker
isolate; only JSON-compatible snapshots and command replies cross back. An
isolate exit or startup failure is retried with 1 s→30 s capped backoff and
never more than one spawn in flight; the recovery-paused start is replayed and
a valid snapshot resets the backoff. StatusNotifier's default is the worker
path: it owns the only D-Bus client and watcher objects and crosses bounded
snapshot/menu/command payloads, while icon files stay UI-decoded. The worker
starts only with the configured tray module's `TrayStarted`; the local service
remains for tests. Live tray verification remains deferred.

**Workspaces.** Sway/i3 IPC, Hyprland sockets, and niri's event stream are
event-driven. All three dedup snapshots against the last emission; niri's
repeated `WorkspacesChanged` lines no longer repaint the rail, while a changed
snapshot or a reconnect replay with different state still emits. 1 MiB reply
caps and 32 ms Hyprland debounce bound the rest.

## Startup and shutdown cost

**Current startup order.** Native installs the method channel and idle
observer, then shows the bootstrap view; the engine starts there. Strips and
overlays use `fl_view_new_for_engine`. A monitor's connector name is resolved
once with a `wl_registry` attach and two `wl_display_roundtrip` calls, then
cached per `GdkMonitor`; repeated `outputs()`/`surfaceCreate` calls reuse it.
An empty cached string is the no-connector sentinel. Monitor add/remove
invalidates the entry and dispose frees the table. Dart probes idle once with a
1 s timeout before `runWidget`. The entrance animation starts with the first
pills.

**Current reload.** `_apply` reconciles native outputs on the first apply and
whenever `OutputsConfig` changed; a settings-only reload applies blocs without
calling `outputs()`. Disruptive edge/thickness/layer/keyboard changes still
recreate surfaces, and `didChangeMetrics` continues to reconcile when the bar
view set changes.

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
- background worker shutdown is generation-safe, but `invoke` has no
  per-request timeout.

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

- tray: 64 items, 64 decoded icons, 256 paths, 8 MiB source file, 512 px D-Bus
  pixmap input dimension, 4096 px raster file dimension, 4,194,304 raster file
  pixels, 24 px preferred output dimension, 64 px hard output cap;
- pip artwork: 16 entries, 8 MiB, 14 px;
- CPU/GPU: 45 history samples each;
- settings: current + last-good + `.prev`, no history;
- OpenCode: 60 s poll, 1 MiB response cap;
- MPRIS: 16 players;
- workspaces: 1 MiB reply cap, 32 ms Hyprland debounce;
- control socket: 2 s client timeout;
- background worker: 10 s startup timeout, per-invoke deadline covering
  startup plus execution, NVML 2 s request timeout, 60 s NVML cooldown after a
  timeout.

**Current — wallpaper accent caps and oversized thumbnails.**
`readWallpaperSource` stats the file before opening, rejects anything over
64 MiB, and reads at most 64 MiB + 1 byte so a file that grew after the stat is
discarded rather than retained. `WallpaperSourceLimits` rejects sources over
16384 px on either side or 40 MP before a codec is instantiated; the codec
decodes only the first frame and scales the longest side to 64 px for the pixel
scan. The bloc debounces cache changes by 300 ms and caches eight paths by
mtime.

A source over the byte cap is not read into Dart. `ProcessWallpaperThumbnailer`
asks `magick` for `"path[0]"` at 64x64 with 64 MiB memory/map limits, or falls
back to `ffmpeg` with one frame and a 64x64 aspect-preserving scale. It uses
binary `Process.run` stdout, a 20 s timeout, an 8 MiB output cap, and probes
each binary once. If both are unavailable or the output is invalid/oversize,
the source is rejected and the output falls through to grim and then the
configured accent. Grim captures with global `-g` coordinates from
`LayerOutput.x/y`; it never combines `-o` and `-g` (this grim rejects that
pair).

The runtime proof for `/home/daze/Personal/Pictures/night_city.gif` (268,902,170
bytes, 3840x2160) in an isolated hidden bar produced wallpaper accent
`#636ea6` (canonical seed from the muted blue/purple first frame) with VmHWM
167,452 kB. The GIF was opened only by external decoder child PIDs, not the bar.
This is a fixed scenario, not a memory budget; the earlier 269 MB/1.64 GiB
observation remains the reason for the cap.

**Current — tray decode and property caps.** `_decodeIconFile` reads intrinsic
dimensions through `ImageDescriptor.encoded`, rejects non-positive, over
4096 px, or over 4,194,304-pixel sources before creating a codec, scales both
target dimensions from one 24 px longest side, decodes one frame, and disposes
the buffer, descriptor, codec, and image. `retainStatusNotifierItemProperties`
keeps only `_knownItemProperties`, so arbitrary `GetAllProperties` values are
not retained; pixmaps are still removed from the map after decode. The SVG
path is unchanged. `SystemTrayIconPixmap` computes a 32-bit FNV-1a digest once
at construction; equality checks identity/dimensions/length then digest and
falls back to full bytes only on a digest match (collision safety), and
`hashCode` uses dimensions plus digest. `_RawTrayIcon.didUpdateWidget` compares
pixmaps instead of scanning RGBA itself.

**Observation, not a budget.** One runtime snapshot measured ~162 MB RSS,
~93 MB PSS, and 313 MB swap. VmHWM reached ~1.64 GiB, which is not a baseline
and must not be published as one. Re-measure with the wallpaper caps in place
and a fixed scenario (5 min idle, one wallpaper change, two overlay cycles),
and record the scenario with the number.

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
per-frame or per-sample logging.

## Measurement protocol

Before changing a performance path, record the baseline; after, repeat the
same scenario and keep the numbers with their provenance.

- Use a profile build for frame timings, a release build for live behavior.
- Record Flutter version, output resolution, scale, refresh rate, scenario,
  and whether blur was active.
- Use `SchedulerBinding.addTimingsCallback` for build/raster/vsync; use
  temporary counters only to prove rebuild scope.
- Use `flutter run --trace-to-file=<path>` for a Perfetto-format timeline when
  frame ordering matters; keep the timings callback for summary numbers.
- Add `TimelineTask` or `Timeline.startSync` events around the scope under
  test (one pill, one overlay) so the trace names it instead of showing bare
  frames.
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
| Reduced motion zeroes every timed transition | Current | `Motion.duration`, entrance dependency gate, settings `MediaQuery.fromView`; reduced-motion widget tests |
| Clock only rebuilds its pill | Current | Shared `ClockBloc`, pill-local builder |
| Visualizer 30 Hz only playing+visible | Current | 33 ms pump, FFT isolate, visibility gate |
| Worker-exit capture teardown and visualizer restart | Current | `BandAnalyzer.failures`, generation guard, capped `VisualizerBloc` retry |
| CPU/GPU pause on seat idle | Current | `SeatIdleBloc` + samplers |
| Battery 5 s async sysfs, not UPower | Current | `battery.dart`; async reads, generation guard, dedup |
| Battery/OpenCode idle gating | Current | `SeatIdleBloc` + sampler `start(paused:)`/`pause`/`resume` |
| MPRIS recovery idle gate | Current | `MediaPlayerService.pauseRecovery`/`resumeRecovery` + `SeatIdleBloc`; signals stay live |
| MPRIS worker crash recovery | Current | `MediaPlayerWorkerProxy`; 1 s→30 s capped single-flight respawn, paused-start replay, unavailable on failure |
| Blur capability-gated, per-pill region | Current | Runner + `BlurRegionController`; not active on host |
| Blur region cache | Current | `(bounds, radius)` rows, dirty/structural flush; unchanged bounds do not rebuild |
| Tray 64/256/8 MiB caps plus 4096 px/4.2 MP raster, known-property retention, digest equality | Current | `_StatusNotifierLimits`, `_decodeIconFile`, `retainStatusNotifierItemProperties`, `SystemTrayIconPixmap` |
| Wallpaper caps plus external 64 px thumbnail for oversized sources | Current | `readWallpaperSource`, `WallpaperSourceLimits`, `ProcessWallpaperThumbnailer`; 269 MB GIF → `#636ea6`, VmHWM 167,452 kB |
| Connector lookup cached per monitor | Current | `connector_cache`; add/remove invalidation, dispose free |
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

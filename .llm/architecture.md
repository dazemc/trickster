# Trickster architecture

Domain knowledge subordinate to `AGENTS.md` and `.llm/workflow.md` (see
`AGENTS.md` → Instruction precedence); on a conflict the higher document wins
and this file is corrected.

## How to read this base

Every statement carries one of three states:

- **Current** — verified in the tree at the commit that wrote this file.
- **Gap** — a known divergence, tracked in `.llm/suggestions.md`.
- **Aspiration** — design intent; never cite it as shipped behavior.

The base is intentionally small:

- `architecture.md` — process, surface, state, capability, workspace, and
  transport shape.
- `performance.md` — frame ceiling, cost model, rebuild algebra, cadence,
  memory, assets, measurement.
- `configuration.md` — file grammar, reload, CLI, and control socket.
- `porting.md` — the Denial boundary and the divergences that are deliberate.
- `workflow.md` — branches, slices, proof, commits, build environment.
- `docs.md` — documentation index and verification rules.
- `todo.md` — authorized work only.
- `suggestions.md` — open findings and proposed constitution corrections.

There is no phase ledger. Git history is the record.

## Guest contract

**Current.** The bar is one Linux process with one Flutter engine, one UI
isolate, and one raster thread. The engine hosts several `FlView`s: a
bootstrap view, one strip per hosted output, and transient overlay views. The
settings application is a separate process with its own engine and no strip
surfaces. Frame cost is process-wide and additive, not per-output; see
`performance.md`.

Dart owns visual policy, module state, and configuration. The host compositor
owns KMS, input seats, presentation, and every other surface. Trickster never
holds a Wayland resource, DRM fd, or client buffer.

## Surface graph

**Bootstrap.** The runner creates the first view with `fl_view_new(project)`
and retrieves the implicit engine with `fl_view_get_engine`. There is no
`fl_engine_new` call. The bootstrap window is a 1×1 background-layer
layer-shell window: transparent, click-through, never meant to be seen. It
hosts the engine's implicit view (`viewId` 0), which keeps the engine alive
when no strip is mapped. View 0 is never destroyed; unhosted outputs hide it
through `surfaceVisible` instead.

**Startup order.** The engine starts on the bootstrap view as soon as that
view is shown and plugins are registered. Strips are created and mapped in the
same GTK activate turn, before Dart IPC begins. The earlier claim that the
engine waits for the first strip's initial configure was wrong; the one-turn
Hyprland write rule is still required because a silent command connection can
block the compositor.

**Strips.** Every hosted output gets one `fl_view_new_for_engine(engine)` view
inside its own layer-shell window. The exclusive zone equals the laid-out
strip. Strips are the only surfaces that may receive the native backdrop
effect.

**Overlays.** Tray menus, tray tooltips, the clock calendar, and the volume
slider each get an independent, transient `fl_view_new_for_engine(engine)` view
on its own fullscreen layer-shell surface. A surface is anchored to the edge
opposite the strip so the strip band remains clickable. It stays hidden until
its Dart session is ready, so no default frame is shown. Menus take exclusive
keyboard and the full input region; tooltips take no keyboard and an empty
input region, so hovering one cannot steal the pointer. Overlays never take
the native blur effect: an effect on a hidden overlay black-screens it.

**Overlay coordination.** One app-owned `OverlayCoordinator` arbitrates the
four overlay blocs. Tray menu, calendar, and volume slider are modal: at most
one owns the slot, and an open modal excludes tooltips. A modal request
closes the active tooltip first, then the previous modal; a tooltip request
behind a modal is refused. Same-kind requests retarget or replace their own
surface without touching another kind. Dismissals are generation-safe and
bounded by a short timeout; failed opens, dismissals, closes, and
retained-view clears release the claim.

**Settings.** The settings process creates its window with
`fl_view_new(project)`, registers plugins on that view, and builds one `View`
for the single reported view. It has no bootstrap surface, no strips, and no
bar engine.

## Surface reconciliation

**Current.** `didChangeMetrics` rebuilds the root and compares the live bar
views with the remembered set. Overlay views are excluded from that set, so a
menu opening does not reconcile outputs. `_reconcileOutputs` is serialized:
a request that arrives mid-pass sets `_reconcileAgain` and runs once more.

For each enumerated output:

- hosted and missing a surface → create it;
- hosted and hidden → show it;
- unhosted with view 0 → hide it;
- unhosted with a destroyable view → destroy it.

A disruptive change (edge, thickness, layer, keyboard, output set) destroys
every strip before creating replacements. Applying a new size to a mapped
strip makes GTK wait for a frame at the new size while Flutter still renders
the old one, which aborts; the engine survives on the bootstrap view.

The strip grows past its configured thickness when the zones wrap, and asks
for a new surface thickness once per distinct target. A hidden configuration
sets thickness 0 and releases the exclusive zone before the surface is
unmapped.

## State graph

**Current.** `flutter_bloc` carries every piece of observable state in both
processes: explicit events and states, one `BlocProvider` per seam, reads
through `watch`, `select`, or `BlocBuilder`. Cubits, `ChangeNotifier`,
`InheritedNotifier`, and `setState` for state another widget or the control
socket can observe are forbidden. Only per-frame widget-local details
(animation controllers, hover and press flags) stay in `State`.

`ModuleScope` builds one provider per configured module and nothing for a
disabled one. GPU and VRAM are the exception: they share one `GpuBloc`, with
the sampler reading only the fields the configured modules need. Shared
services — settings document, wallpaper accent, tray menus, tooltips,
calendar, volume slider — are blocs too. The settings application carries its
own blocs under the same rule.

States that cross a process, control-socket, or diagnostic boundary are
JSON-shaped. The convention lives on the state's model type
(`BatteryStatus`, `CpuSample`, `RamSample`, `TemperatureSample`, `DiskSample`,
`GpuState`, `WorkspacesState`, and peers), not on every bloc class.

Debug and profile builds trace every bloc event, transition, error, and
lifecycle to stderr through `TricksterObserver`; release stays silent. Read
the transcript to verify behavior, not pixels.

## Capability contracts

**Layer shell.** The strip is a `zwlr_layer_shell_v1` client through
`gtk-layer-shell`. Without the protocol there is no bar surface; never fall
back to an X11 or managed toplevel.

**Backdrop blur.** The host must advertise `ext-background-effect-v1` **and**
the blur capability bit. A manager global alone is not enough. The effect is
set per strip as a region of pill rectangles; overlays are excluded. Without
the capability the pills paint a translucent gradient and no native effect.
The registry stays alive: removing the manager destroys every strip, overlay,
and settings effect, drops the proxy, and announces `blurChanged` false; a
re-advertised manager rebinds and re-announces support so Dart re-sends its
cached regions.

**Seat idle.** Native binds every advertised `wl_seat` at version 1 and
creates one inhibitor-aware `ext-idle-notify-v1` notification per seat with a
60 s timeout. The observer reads no input devices and never installs an
inhibitor. The aggregate is idle only when at least one seat is bound and
every seat has a live notification reporting idle; any resume, seat removal
or reset, or notifier loss falls back to false. Late seats bind, removed
seats are destroyed, and a new notifier recreates notifications for the bound
seats. A missing protocol means samplers keep their normal cadence. The
settings process does not install the observer.

**Sink volume.** The default sink is watched over PipeWire while the media
module is configured. The watcher tracks the bound metadata, node, and device
global ids; every proxy carries removed/destroy watches, so a global removal
clears its reading and a re-advertised default binds a fresh proxy.

**Control socket.** One server owns
`$XDG_RUNTIME_DIR/trickster/control.sock`. A live socket is probed before
binding; only a socket this server owns is unlinked on dispose. An accept
stream that errors or closes is rebound after a capped 500 ms–30 s backoff;
dispose cancels the retry, and a live foreign owner is never stolen.

## Workspaces

**Current.** The workspace rail is an honest replacement for Denial's native
workspace state. Three backends are implemented and auto-detected:

- Sway/i3 IPC over the Unix socket: event stream plus one-shot commands.
- Hyprland: `.socket.sock` for one-turn commands, `.socket2.sock` for events.
- niri: the JSON event stream and one-shot action connections.

All three are event-driven; there is no interval poll. The rail mirrors the
workspaces the compositor places on each output. Focus requests use a
dedicated one-shot connection so the event stream stays subscribed.

**Decision.** `ext-workspace-v1` is deferred. The protocol gives event-driven
workspace state, but it exposes no occupied bit while the rail renders
occupied and empty pips. Switching Hyprland off the JSON IPC backend would
regress the rail. Revisit only if the protocol gains occupancy or the pip
model stops needing it.

**Gap.** River and COSMIC are layer-shell hosts, not implemented workspace
backends. Do not describe them as supported rails.

## Transport

**Current.** The bar's control server speaks one JSON request line and one
JSON reply line. It serves `version`, `status`, `reload`, settings read/write,
and outputs read/write. The settings application prefers the socket and falls
back to the file transport on the first `ControlSocketException`, including a
save after the bar exits. The fallback is sticky for the session; there is no
mid-session re-probe. Both paths implement the same transport interfaces and
the revision retry stays in `NativeSettingsStore`.

One settings revision line covers both processes and the bar's own writes (the
media pill's mode cycle). A revision mismatch is a retryable `StateError`;
the store retries once and never keeps a document history.

**D-Bus tray.** The StatusNotifier service owns one session client per
connection and still runs on the UI isolate. Its UI boundary is
`StatusNotifierClient`: tray models live in `status_notifier_models.dart`,
icon-file/SVG decoding lives in `tray_icon_decoder.dart`, and the service keeps
D-Bus pixmap decoding and icon-path resolution. `TrayBloc` depends on the
interface; production defaults to the worker proxy while the local service is
retained for tests and injected use. A transport failure discards that client,
recreates the watcher endpoint and signal subscriptions, re-registers the
preserved item addresses, and clears stale items and pending refreshes. A
cheap `GetId` heartbeat detects a silent bus drop.

**StatusNotifier worker.** `StatusNotifierWorkerProxy` spawns one
`trickster-sni-worker` isolate that owns the only `DBusClient`, watcher
endpoint, registrations, property/menu parsing, and heartbeat. Bounded
protocol payloads carry commands, replies, snapshots, menu entries, and icon
payloads; icon-name paths cross as paths and are decoded by `TrayIconDecoder`
on the UI isolate. The proxy spawns the worker only when the configured tray
module receives `TrayStarted`, respawns after isolate death with 1 s→30 s
capped backoff, and sends a dispose command before killing it. A disabled tray
creates no bloc or worker. Live tray verification remains deferred.

**MPRIS worker.** MPRIS runs in a dedicated widget-free worker isolate: its
service and only DBusClient live there, snapshots cross back as JSON-compatible
`MprisPlaybackState` maps, and controls/recovery travel to the worker as
commands. A transport failure cancels its owner/properties subscriptions,
clears the active player, emits unavailable, then re-subscribes and
rediscovers on a fresh client inside the worker. Its 60 s refresh remains the
only discovery cadence. The UI proxy spawns the worker only when the media
module starts. If the isolate errors, exits, or fails during startup, the
proxy fails pending requests, tears down that connection, emits unavailable,
and respawns once per attempt with 1 s→30 s backoff and a single in-flight
spawn. It preserves the recovery-paused flag for the replayed `start`, resets
the backoff after a valid state snapshot, and never respawns for a normal
worker command or an in-worker D-Bus failure. Dispose cancels the retry and
kills the worker.

## Resource ownership

**Current.** Ownership is split so every long-lived object has one owner:

- Native runner: engine, bootstrap/strip/overlay views, layer-shell windows,
  blur effect and regions, idle registry/seats/notifier, PipeWire capture and
  volume streams.
- Dart bar app: config watcher, control server, overlay coordinator and blocs
  (tray menu, calendar, volume slider, tooltip), wallpaper accent bloc,
  settings and outputs transports.
- MPRIS worker isolate: `MediaPlayerService`, its DBusClient, snapshots, and
  recovery timers; only JSON-compatible state and command replies cross back.
- Module blocs: their sampler, D-Bus client, socket, worker isolate, or timer.
- `PipArtworkCache`: process-wide bounded cache, intentionally alive until
  process exit.

The bar app's post-frame startup is mounted-guarded: a dispose before the
first callback constructs no config watcher or control server, so dispose owns
only resources that actually exist.

A service may be shared, but its dispose path must still be owned by the bloc
or scope that created it. The native runner owns resources Dart cannot see;
the overlay lifecycle gap above shows what happens when that ownership is not
paired.

A module `*Stopped` event is terminal for its bloc: the bloc marks itself
stopped, cancels its snapshots subscription, and disposes its
sampler/service/monitor/worker exactly once. Later Started, Paused, Resumed,
sample, focus, or refresh events are ignored, and `close()` after a stop must
not dispose twice. Closing without a stop keeps the normal teardown. No
production path emits `Stopped` today.

## Non-goals

Not a compositor, not a Quickshell config, not a Denial component, not a
general Flutter application. See `AGENTS.md` for the authoritative list.

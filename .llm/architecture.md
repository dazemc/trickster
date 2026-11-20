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
and takes its engine. The bootstrap window is a 1×1 background-layer
layer-shell window: transparent, click-through, never meant to be seen. It
hosts the engine's implicit view (`viewId` 0), which keeps the engine alive
when no strip is mapped. View 0 is never destroyed; unhosted outputs hide it
through `surfaceVisible` instead.

**Strips.** Every hosted output gets one `fl_view_new_for_engine(engine)` view
inside its own layer-shell window. The exclusive zone equals the laid-out
strip. Strips are the only surfaces that may receive the native backdrop
effect.

**Overlays.** Tray menus, tray tooltips, the clock calendar, and the volume
slider each get a transient `fl_view_new_for_engine(engine)` view on a
fullscreen layer-shell surface. A surface is anchored to the edge opposite
the strip so the strip band remains clickable. It stays hidden until its Dart
session is ready, so no default frame is shown. Menus take exclusive keyboard
and the full input region; tooltips take no keyboard and an empty input
region, so hovering one cannot steal the pointer. Overlays never take the
native blur effect: an effect on a hidden overlay black-screens it.

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
disabled one. Shared services — settings document, wallpaper accent, tray
menus, tooltips, calendar, volume slider — are blocs too. The settings
application carries its own blocs under the same rule.

States that cross a process, control-socket, or diagnostic boundary are
JSON-shaped. The convention lives on the state's model type
(`BatteryStatus`, `CpuSample`, `GpuState`, `WorkspacesState`, and peers), not
on every bloc class.

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

**Seat idle.** Native binds `ext-idle-notify-v1` on the first seat with a
60 s timeout. The notification is inhibitor-aware and purely observational: it
reads no input devices and never installs an inhibitor. The observer rebinds
when the compositor removes and later re-advertises the seat or notifier. A
missing protocol means samplers keep their normal cadence. The settings
process does not install the observer.

**Control socket.** One server owns
`$XDG_RUNTIME_DIR/trickster/control.sock`. A live socket is probed before
binding; only a socket this server owns is unlinked on dispose.

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
and outputs read/write. The settings application writes settings and outputs
through the socket and falls back to the file transport when no bar answers.
Both paths implement the same transport interfaces.

One settings revision line covers both processes and the bar's own writes (the
media pill's mode cycle). A revision mismatch is a retryable `StateError`;
the store retries once and never keeps a document history.

## Non-goals

Not a compositor, not a Quickshell config, not a Denial component, not a
general Flutter application. See `AGENTS.md` for the authoritative list.

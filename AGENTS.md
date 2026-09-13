# Trickster

A Flutter-native Wayland status bar.

Trickster begins with a belief: origin does not have to dictate purpose.

Denial was created to own the desktop. Here, its likeness is given a
different life. It does not own outputs, input, or composition. It visits
other compositors as a guest: one layer-shell strip per display, Denial's
pill cards, motion, and module language, without becoming a compositor.

That is the architecture. It is also the meaning of the name.

**Trickster** is Denia's doll from *Wuthering Waves*. Denial owns the
desktop; Trickster carries her likeness into other worlds — Sway, Hyprland,
niri, river, COSMIC.

## Goal

Resemble Denial as closely as a layer-shell client honestly can. Maximize
frame and idle performance. Use memory as if the bar were a compositor
surface, not a desktop app. Prefer a port of Denial's Dart over a rewrite
whenever the code is compositor-agnostic. Do not invent a second design
language.

The work queue lives in `.llm/todo.md`, in build order. Work it top-down one
step at a time, on the branch for its phase (see Repository workflow):

1. Implement the step, nothing more.
2. Prove it statically: `flutter analyze` clean, `flutter test` green
   (plus a release build when native code changes).
3. Prove it at runtime: launch the release bar in the live session, watch
   for runtime errors (stderr exceptions, missing ancestors, dead pills),
   exercise what the step changed, then kill only the Trickster process.
   A step that passes tests but errors at runtime is not done.
4. Re-read `.llm/suggestions.md` and update it — but only if something is
   absolutely needed. Silence is a valid review outcome; never add noise
   to justify the read.
5. Only then remove the step from `.llm/todo.md`.
6. Commit in slices: the code change is one commit; every LLM-maintained
   markdown file (`.llm/todo.md`, `.llm/suggestions.md`, docs) gets its own commit.
   Markdown never shares a commit with code, and two markdown files never
   share a commit with each other.

Never remove an untested step. Never batch multiple steps into one change.
Never check steps off — remove them. Do not let the queue rot.

## What it is

- One Flutter Linux process. One `wlr-layer-shell` surface per connected
  output (layer, anchors, exclusive zone via `gtk-layer-shell` FFI).
- Denial's desktop system bar: floating pill cards, wallpaper-derived or
  configured accent, spring entrance, trailing-edge module cluster.
- Modules in Denial parity: clock, battery (UPower), media (MPRIS), system
  tray (StatusNotifier), CPU/GPU, workspaces.
- Configured like Denial: files on disk. The `TricksterBar(...)` Dart API is
  the typed in-memory model those files decode into, not the user interface.

## What it is not

- Not a compositor. It never owns outputs, input routing, client buffers, or
  work areas. It asks for a strip through layer-shell like any other client.
- Not a Quickshell config. QML is out of scope; the UI language is Dart.
- Not a Denial component. Portable modules may be ported from Denial's
  `dart_shell` (GPL-3.0-or-later, attribution preserved). Compositor-coupled
  code (`denial_bridge`, XEmbed tray merge, native workspaces, atlas/KMS)
  stays behind. Anything ported keeps Trickster GPL-3.0-or-later.
- Not a general Flutter application. No Material scaffolding, no unused
  routes, no settings window in v1, no second engine, no debug overlay in
  production.

## Architecture

```text
trickster
  Dart bootstrap
    session.conf / outputs.conf / settings.json
    layer-shell surfaces (one per output)
    Riverpod module graph
    control socket (tricksterctl)

  Host compositor
    zwlr_layer_shell_v1
    exclusive zone, anchors, keyboard interactivity
    composition of the strip with the rest of the desktop
```

Dart owns visual policy, module state, and config. The host compositor owns
KMS, input seats, and every other surface. Trickster never holds a Wayland
resource, DRM fd, or client buffer.

Resemble Denial at every seam that does not require compositor ownership:

- Same widget split: strip paints nothing; modules are borderless pills.
- Same Riverpod provider seams and `select` watches as
  `desktop_system_bar.dart`.
- Same theme tokens, motion springs, and accent model.
- Same config layers, file grammar, and CLI scheme.
- Same D-Bus services (UPower, MPRIS, SNI, and later BlueZ/NetworkManager)
  where Denial already spoke D-Bus.
- Workspaces via compositor JSON-over-unix-socket backends (Sway, Hyprland,
  niri), auto-detected — the honest replacement for Denial's native state.
- Backdrop blur only when the host advertises `ext-background-effect`;
  otherwise translucent fill. Never fake blur with a full-screen copy.

## Configuration (Denial mirror)

File style is Denial-style `KEY=VALUE` with `#` comments.

- `/etc/trickster/session.conf` (`TRICKSTER_*`): machine env — config-path
  override, layer, namespace, keyboard interactivity, accent override, log
  filter. Packaged template, `backup=`-preserved. Parsed by the Dart
  bootstrap at startup.
- `$XDG_CONFIG_HOME/trickster/outputs.conf`: bar placement with Denial's
  `system_bar=` grammar verbatim (`top,32`; `bottom,40,eDP-1`; `hidden`).
  Template copied to the user config on first launch, never overwritten.
  Strip math is ported from Denial's `display_layout.dart`; the "work area"
  becomes the layer-shell exclusive zone.
- `$XDG_CONFIG_HOME/trickster/settings.json`: versioned settings document.
  Port Denial's `settings_store.dart` (`NativeSettingsStore` +
  `SettingsDocumentTransport`) nearly verbatim — one async write queue,
  `expectedRevision` check-and-retry, full-document push into Riverpod.
  Transport v1 is direct-file (single owner); keep the transport interface
  so a socket transport can slot in later unchanged. Retain only the current
  revision and one last-good snapshot. Never keep a document history.
- CLI mirrors `denial-session`/`denialctl`: `trickster --check` (layer-shell
  advertised? gtk-layer-shell loadable? outputs visible? config parseable?),
  `--version`, `--config PATH`, one-shot overrides; `tricksterctl
  status|reload|version` over `$XDG_RUNTIME_DIR/trickster/control.sock`.

Live reload: `dart:io` watcher on the config dir (200ms debounce). Hot keys
(accent, module list/order, clock format, thresholds) rebuild providers.
Disruptive keys (edge, layer, exclusive size, output set) destroy and
recreate only the affected layer surface. Invalid files keep last-good state
and log; never crash the bar.

## Performance

The strip is small. Waste is still forbidden. Treat idle CPU and frame cost
as first-class bugs.

- Production builds are AOT release. Do not ship JIT, profile, or
  debug-engine artifacts in packages.
- One Flutter engine, one isolate, one process. `tricksterctl` is a short
  client against the control socket, never a second UI runtime.
- Do not start a module that is not configured. Disabled modules have zero
  subscriptions, zero timers, zero D-Bus names.
- Rebuild only the module whose data changed. Use Riverpod `select`,
  `RepaintBoundary` around each pill, and a clock that ticks inside its own
  widget — never rebuild the strip on a 1 Hz clock.
- Prefer D-Bus signals and compositor IPC events over polling. `/proc` and
  sysfs samples are bounded (CPU/GPU at 1 Hz, shared across cards). Reuse
  read buffers; do not allocate a new string per sample if a reused buffer
  will do.
- Workspace backends are event-driven sockets (Sway/i3 IPC, Hyprland,
  niri). No interval polls when the compositor can push.
- Exclusive zone equals the laid-out strip. Do not reserve more than the
  pills occupy. Destroy surfaces for disconnected outputs immediately.
- Frame scheduling follows the output that hosts the surface. Do not run
  vsync work for outputs that have no bar.
- Backdrop blur, shadows, and clips are opt-in and host-dependent. Default
  path is fill + border, matching Denial's pills when blur is unavailable.
- Log in production only on state changes and errors. No per-frame or
  per-sample logging.

## Memory

Resident size should look like a bar, not like a Flutter gallery.

- Dispose every D-Bus connection, stream subscription, file watcher, IPC
  socket, and `LayershellWindowController` in the same scope that created
  it. Leaks in those objects are release blockers.
- Cache tray pixmaps and decoded images at display size with a hard cap and
  eviction. Do not retain raw D-Bus byte arrays after decode.
- Do not copy Denial's entire `dart_shell`. Port only the bar, theme,
  tokens, motion, and the compositor-agnostic services those modules need.
- No Material `Icons` font if a smaller subset or Denial's existing font
  stack covers the glyphs. Bundle only fonts and assets the bar paints.
- Settings documents: current + last-good only. Config parse trees are
  discarded after they become the typed model.
- Release packages are stripped. `options=('!strip')` is not the default
  here; Denial retains symbols because it is a compositor. A bar does not
  get that exception without a measured reason.
- Never hold previous frames, screenshot bitmaps, or offscreen copies of
  the host wallpaper unless a measured accent sampler is enabled — and then
  only a downscaled working buffer, freed after the accent is committed.

## Porting from Denial

When a Denial file is compositor-agnostic, port it. When it is not, write
the smallest honest replacement and keep the same type names at the module
boundary so the widgets do not care.

Port: pill cards, theme tokens, motion, clock, UPower, MPRIS, SNI tray
service, CPU/GPU status, settings store shape, `system_bar=` grammar,
layout strip math.

Replace: `denial_bridge` workspaces → compositor IPC; wallpaper accent →
configured color plus optional local sampler; XEmbed tray → omit; exclusive
zone → layer-shell request.

Do not add features Denial's bar does not have until parity is real.

## Repository workflow

- `main` is the stable branch. Each TODO phase gets its own branch from
  `main`: `bar/phase-1`, `bar/phase-2`, `bar/phase-3`, `bar/phase-4`,
  `bar/phase-5`.
  All of the phase's steps land on that branch — never on `main`, never on
  another phase's branch.
- Never start a new phase without the user's explicit go-ahead in chat: no
  branch, no first step, until asked. Merging a finished phase likewise
  waits for confirmation.
- Commit every finished TODO step on the phase branch as a slice: one commit
  for the code, then one commit per touched LLM-maintained markdown file
  (`.llm/todo.md`, `.llm/suggestions.md`, docs). A step is finished only when
  it is implemented, proven (`flutter analyze` clean, `flutter test` green),
  and removed from `.llm/todo.md`. No direct pushes to `main` beyond initial
  scaffolding.
- When a phase's steps are all landed and removed, merge the phase branch
  back into `main` through a pull request, then branch the next phase fresh
  from the updated `main`.
- Commits use the contributor's configured Git identity. Follow
  `scope: summary` in the imperative.
- Any update to `AGENTS.md` itself is committed immediately, in its own
  commit, in the same session — a constitution change never sits uncommitted
  in the tree. The same applies to every file under `.llm/`: one file per
  commit, committed in the same session as the edit, never bundled with
  code or with each other.
- Keep the tree `flutter analyze`-clean. Widget tests cover layout math,
  config parse/round-trip, settings revision retry, and module state
  mapping. Run `flutter analyze` and `flutter test` before pushing.
- Networked Git/GitHub commands (`fetch`, `push`, `gh`) run outside any
  sandbox; sandboxed credential or network failures are not authoritative.

## Graphical session control

Never log out, terminate, restart, or otherwise stop the user's local
graphical session on the user's behalf. When testing requires restarting the
bar, kill only the Trickster process — never the compositor — and wait for
explicit confirmation before touching session targets, the display manager,
reboot, or power off.

## Build

```sh
flutter analyze
flutter test
flutter run -d linux          # Wayland session with layer-shell support
flutter build linux --release # production AOT
```

A first build requires network access (pubspec + Flutter SDK); subsequent
builds reuse the cache. The runtime requires `gtk-layer-shell` and a
compositor advertising `zwlr_layer_shell_v1`.

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
step at a time, on the working branch (see Repository workflow):

1. Implement the step, nothing more.
2. Prove it statically: `flutter analyze` clean, `flutter test` green
   (plus a release build when native code changes).
3. Prove it at runtime: launch the release bar in the live session, watch
   for runtime errors (stderr exceptions, missing ancestors, dead pills),
   exercise what the step changed, then kill only the Trickster process.
   A step that passes tests but errors at runtime is not done. If the
   done-criteria needs eyes on screen, hand the user the exact run-and-look
   commands and wait for their verdict — never substitute screenshots.
4. Re-read the topical notes under `.llm/` and update the matching file —
   but only if something is absolutely needed. `.llm/suggestions.md` is for
   agent-proposed, user-reviewed findings that may escalate to `todo.md`.
   Silence is a valid review outcome; never add noise to justify the read.
5. Only then remove the step from `.llm/todo.md`.
6. Commit in slices: the code change is one commit; every LLM-maintained
   markdown file (`.llm/todo.md`, `.llm/suggestions.md`, docs) gets its own commit.
   Markdown never shares a commit with code, and two markdown files never
   share a commit with each other.

Never remove an untested step. A step is one action with one done-criterion;
split work that spans backends, services, or widgets into separate steps.
Never batch multiple steps into one change. Never check steps off — remove
them. Do not let the queue rot.

## What it is

- One Flutter Linux process runs the bar: one `wlr-layer-shell` strip
  surface per connected output (layer, anchors, exclusive zone via
  `gtk-layer-shell` FFI), plus a transient overlay surface while a tray menu
  is open. Never a second strip surface, never a second bar engine.
- Denial's desktop system bar: floating pill cards, wallpaper-derived or
  configured accent, spring entrance, trailing-edge module cluster.
- Denial's settings application in parity: the same binary run in settings
  mode (`trickster-settings`, i.e. `trickster --settings`). It is its own
  process with its own engine and no strip surfaces, writing the same
  documents through the control socket (falling back to the file transport)
  and speaking the same design language. It covers exactly the settings the
  bar has — never compositor controls it does not own.
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
  routes, no debug overlay in production. The settings application is a
  standalone process (above); it is never a window inside the bar process
  and never a second bar engine.

## Architecture

```text
trickster
  Dart bootstrap
    session.conf / outputs.conf / settings.json
    layer-shell surfaces (one strip per output, transient menu overlays)
    flutter_bloc module graph
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
- Same widget split and per-module state seams as
  `desktop_system_bar.dart`, carried by `flutter_bloc`: one `BlocProvider`
  per configured module, explicit events and states, `watch` / `select` /
  `BlocBuilder` reads — no Cubits.
- Every bloc state ships `toJson`/`fromJson` from day one (convention only,
  no HydratedBloc) so `tricksterctl status` reads real state later.
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
  `expectedRevision` check-and-retry, full-document push into the settings
  bloc. Transport v1 is direct-file (single owner); keep the transport interface
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
- One Flutter engine, one UI isolate, one process — per process. Blocking
  OS work that must never stall the frame loop (Hyprland IPC, NVML) may run
  on worker isolates; they host no widgets and no second engine.
  `tricksterctl` is a short client against the control socket, never a
  second UI runtime. The settings application hosts its own engine only
  while it is open; it never hosts the bar.
- Do not start a module that is not configured. Disabled modules have zero
  subscriptions, zero timers, zero D-Bus names.
- Rebuild only the module whose data changed. Use bloc `select`,
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
  per-sample logging. Debug/profile builds trace every bloc event,
  transition, error, and lifecycle to stderr (`TricksterObserver`); release
  stays silent.

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

## Instruction precedence

One explicit hierarchy, from most to least authoritative. A lower file never
overrides a higher one; on a conflict the higher file wins and the lower one
is corrected in the same session.

```text
AGENTS.md             authoritative rules — the constitution
.llm/workflow.md      process interpretation of those rules
.llm/*.md             domain knowledge and contracts
.llm/todo.md          currently authorized work, in build order
.llm/suggestions.md   non-authoritative observations
```

- `AGENTS.md` is authoritative. It answers what the project is and how every
  change is made.
- `.llm/workflow.md` interprets the process — branches, commits, phases — and
  never adds or bends a rule.
- `.llm/architecture.md`, `configuration.md`, `performance.md`,
  `porting.md`, and `docs.md` hold domain knowledge and contracts derived
  from the constitution.
- `.llm/todo.md` grants exactly the work it lists, top-down, one step at a
  time; a step never authorizes more than itself.
- `.llm/suggestions.md` is non-authoritative. Entries inform decisions but
  bind nothing until the user escalates them.

## Repository workflow

- `main` is the stable branch. Exactly one working branch, `working`, exists
  beside it and carries the code steps of the phase at the top of
  `.llm/todo.md` that still has steps. No other branches exist (no per-phase
  `bar/phase-N` branches).
- Code lands on `working`; markdown lands on `main`. `AGENTS.md`, every file
  under `.llm/`, and docs pages commit directly on `main`, immediately, one
  file per commit, and are pushed. After each markdown commit, merge `main`
  back into `working` so the tree keeps reading current docs.
- Never start a new phase without the user's explicit go-ahead in chat: no
  branch, no first step, until asked. Merging a finished phase likewise
  waits for confirmation.
- Commit every finished TODO step as a slice: one code commit on `working`,
  then one commit per touched markdown file on `main` (switch to `main`,
  commit, push, switch back, merge `main` into `working`). A step is
  finished only when it is implemented, proven (`flutter analyze` clean,
  `flutter test` green), and removed from `.llm/todo.md`. Markdown never
  shares a commit with code or with another markdown file.
- When a phase's steps are all landed and removed, merge `main` into
  `working` first so the PR carries code only, merge `working` into `main`
  through a pull request, then reset `working` to the updated `main` for
  the next phase. No branch is created per phase.
- Every merge to `main` updates the docs it invalidates. Before merging
  (a step, a phase, or a fix), walk `docs_site/content/` for claims the
  change makes stale and land the corrections on `main`, one file per
  commit, pushed — docs never trail the code.
- Commits use the contributor's configured Git identity. Follow
  `scope: summary` in the imperative.
- Any update to `AGENTS.md` itself is committed immediately on `main`, in
  its own commit, in the same session — a constitution change never sits
  uncommitted in the tree. The same applies to every file under `.llm/`.
- Keep the tree `flutter analyze`-clean. Widget tests cover layout math,
  config parse/round-trip, settings revision retry, and module state
  mapping. Run `flutter analyze` and `flutter test` before pushing.
- Keep pub packages current. Before starting a change, run
  `flutter pub upgrade`; verify with `flutter pub outdated` that no
  resolvable package lags. Commit `pubspec.lock` (and `pubspec.yaml` when a
  constraint moves) on its own. Never `dependency_overrides` a Flutter SDK
  pin.
- After every change, review the touched code for misses (Denial parallels,
  performance traps, config warts, docs gaps) and append anything that meets
  the bar to `.llm/suggestions.md`; findings never live only in the
  transcript.
- After each phase is merged, walk every open suggestion with the user and
  settle its decision — keep, condense, move, escalate, or dismiss — before
  the next phase starts.
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
builds reuse the cache. On a fresh clone, fetch the separate docs-site
project once (`(cd docs_site && dart pub get)`) before running
`flutter analyze`, or its unfetched dependencies show up as analyzer
errors. The runtime requires `gtk-layer-shell` and a compositor
advertising `zwlr_layer_shell_v1`.

Release builds tree-shake the Lucide icon font. Adding a new glyph and
running `flutter build linux --release` without a clean can reuse the
previous subset, shipping the new glyph blank; run `flutter clean` when
icons changed. Fresh checkouts are unaffected.

Never force the bar onto X11 (`GDK_BACKEND=x11`): it renders as a managed
client with no exclusive zone and no anchoring, proving nothing and
misrepresenting the product. Verify visuals on native Wayland only; when the
surface cannot present, verify through the transcript or a probe and fix the
renderer instead of routing around it.

# Trickster architecture

Domain knowledge subordinate to `AGENTS.md` and `.llm/workflow.md` (see
`AGENTS.md` → Instruction precedence); on a conflict the higher document wins
and this file is corrected.

## What it is

- One Flutter Linux process and engine. One `wlr-layer-shell` strip surface
  per connected output (layer, anchors, exclusive zone via `gtk-layer-shell`
  FFI), plus one transient overlay surface while a tray menu is open; all
  created as native multi-view windows (`fl_engine_new` +
  `fl_view_new_for_engine`), never through Flutter's master-only,
  private-import experimental windowing API.
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

## Runtime shape

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

## Observability

Debug/profile builds trace every bloc event, transition, error, and
lifecycle to stderr (`TricksterObserver`, installed in `main`); release
stays silent. Read the transcript to verify behavior, not pixels.

## Denial seams to resemble

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

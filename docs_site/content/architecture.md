---
title: Architecture
description: Guest model, frame path, Denial ports, and performance rules.
---

## Guest, not owner

```text
trickster
  Dart bootstrap
    session.conf / outputs.conf / settings.json
    layer-shell surfaces (one per output)
    flutter_bloc module graph
    control socket (tricksterctl)

  Host compositor
    zwlr_layer_shell_v1
    exclusive zone, anchors, keyboard interactivity
    composition of the strip with the rest of the desktop
```

Dart owns visual policy, module state, and config. The host owns KMS, input seats, and every other surface. Trickster never holds a Wayland resource, DRM fd, or client buffer.

## Frame path

Trickster renders a ~32px strip into client buffers; the host composites it. That is one more composite step than Denial, which renders the whole desktop into a shared GBM atlas scanned out directly. At bar scale the cost is negligible: a frame of latency on updates and a small standing GPU cost, in exchange for running anywhere layer-shell exists.

A cluster that outgrows its share of the strip wraps into rows: the zones clamp around the centered rail and the strip grows past its configured thickness (the exclusive zone follows), shrinking back when the content clears. Nothing scrolls.

The widget split mirrors Denial: the strip paints nothing, modules are borderless pills, each pill repaints only on its own data (`select` watches, `RepaintBoundary` per pill, a clock that ticks inside its own widget).

## State

`flutter_bloc` carries all state in both processes: explicit events and states, no Cubits, no `ChangeNotifier` application state. In the bar, `ModuleScope` builds one provider per configured module, so a disabled module owns no bloc, no subscription, and no timer; the settings application carries its own blocs under the same rule. Every state ships `toJson`/`fromJson` from day one (convention only, no HydratedBloc) so `tricksterctl status` reads real state later.

## Ported vs. replaced

Ported from Denial's `dart_shell` (GPL-3.0-or-later, attribution preserved): pill cards, theme tokens, motion springs, clock behavior, UPower/MPRIS/SNI service shapes, CPU/GPU status, settings-store shape, `system_bar=` grammar, strip math.

Honestly replaced: `denial_bridge` workspaces → per-compositor JSON-over-unix-socket backends; wallpaper accent → configured color plus the optional local sampler (the awww/swww cache, falling back to a `grim` screencopy of the strip band for outputs without a cache image); XEmbed tray → omitted; exclusive zone → layer-shell request.

## Performance rules

- AOT release only. One engine, one UI isolate, one process; blocking OS work (compositor IPC, NVML) runs on widget-free worker isolates.
- Disabled modules start nothing. Event-driven D-Bus and IPC; bounded `/proc` sampling with reused buffers.
- Exclusive zone equals the laid-out strip. Dead-output surfaces die immediately.
- Backdrop blur only with `ext-background-effect`, and only over the pill bounds (a scanline region per card) — never the whole strip; without the protocol the cards fall back to translucent fills. The blurred fill is Denial's dark backing plus a painted rim; no fake backdrop copies. Overlay surfaces (menu, tooltip, calendar) composite translucent fills and never take the native effect.
- Log on state changes and errors only. No per-frame or per-sample logging. Debug/profile builds trace every bloc event, transition, error, and lifecycle to stderr (`TricksterObserver`); release stays silent.

## Memory rules

- Dispose every D-Bus connection, subscription, watcher, socket, and layer controller in the scope that created it.
- Tray pixmaps and decoded images at display size, hard cap, eviction. No raw D-Bus bytes retained.
- Bundle only painted fonts and assets. Release packages stripped.
- Settings: current plus last-good only. No histories, no previous frames, no wallpaper copies.

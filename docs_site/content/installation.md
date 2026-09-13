---
title: Installation
description: Build Trickster Bar from source and run your first bar.
---

## Requirements

- Flutter SDK with Linux desktop support (`flutter doctor` shows a `[✓] Linux toolchain`).
- `gtk-layer-shell` system library (`gtk-layer-shell-0` via pkg-config).
- A Wayland session on a compositor advertising `zwlr_layer_shell_v1` (Sway, Hyprland, niri, river, COSMIC).

## Build

```sh
flutter pub get
flutter build linux --release
```

The bundle lands at `build/linux/x64/release/bundle/trickster`. Run it directly — there is no installer yet:

```sh
./build/linux/x64/release/bundle/trickster
```

First-party packages and an AUR recipe are planned but not published.

## Preflight

Before starting the bar, validate the environment without opening any surface:

```sh
trickster --check
```

Expected output on a healthy session:

```text
ok    wayland: wayland-1
ok    outputs.conf: top,32
ok    settings.json: revision 1
ok    layer-shell: zwlr_layer_shell_v1 advertised
ok    outputs: eDP-1
```

Any failing line exits non-zero with a `fail` reason. The most common failure is running outside Wayland (`WAYLAND_DISPLAY is unset`).

## First launch

On first launch Trickster seeds `~/.config/trickster/` with `outputs.conf` and `settings.json` defaults and shows a top strip with workspaces, CPU, battery, and clock pills. See [Configuration](/configuration) to move it.

## Stopping

Kill only the bar process — never the compositor:

```sh
pkill -x trickster
```

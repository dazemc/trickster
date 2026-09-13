---
title: Development
description: Build, test, packaging, and project rules.
---

## Build and test

```sh
flutter analyze
flutter test
flutter run -d linux          # Wayland session with layer-shell support
flutter build linux --release # production AOT
```

A first build needs network (pubspec + Flutter SDK); later builds reuse the cache. Keep the tree `flutter analyze`-clean. Widget tests cover layout math, config parse/round-trip, settings revision retry, and module state mapping.

Work happens on one branch per phase (`bar/phase-a`, `bar/phase-b`, …), each step committed separately as it lands proven and is removed from `TODO.md`, with the phase merged back into `main` through a pull request when done. Commits follow `scope: summary` in the imperative.

## Project rules

The full constitution lives in [AGENTS.md](https://github.com/dazemc/trickster-bar/blob/main/AGENTS.md). The short version:

- Resemble Denial at every seam that does not require compositor ownership.
- Port compositor-agnostic Denial Dart instead of rewriting it; keep type names at module boundaries.
- No features Denial's bar lacks until parity is real.
- Never stop the user's graphical session on their behalf; kill only the Trickster process when testing.
- Run `gh` and networked Git outside any sandbox.

## Packaging

Planned, not published:

- Source `trickster-bar` PKGBUILD plus a `-bin` AUR path mirroring Denial's split packaging.
- `/etc/trickster/session.conf` ships as a `backup=`-preserved template; `outputs.conf` seeds per-user on first launch.
- Release builds are AOT, stripped, with no JIT/profile/debug artifacts.

## Troubleshooting

| Symptom | Likely cause |
| --- | --- |
| `--check` fails on `wayland` | Not in a Wayland session (`WAYLAND_DISPLAY` unset) |
| `--check` fails on `layer-shell` | Compositor lacks `zwlr_layer_shell_v1`, or `gtk-layer-shell` missing |
| Bar invisible, process alive | `system_bar=hidden`, or all modules disabled/empty |
| Stale pills after editing config | Invalid file — check stderr; last-good state is kept by design |
| No workspaces pill | Unsupported compositor (needs Sway, Hyprland, or niri IPC) |
| No battery pill | Desktop without a `BAT*` sysfs device — expected |

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

Code lands on the single `working` branch; every markdown file commits directly on `main` in its own commit and is merged back into `working`. Each step is committed separately as it lands proven and is removed from `.llm/todo.md`, and a finished phase merges back into `main` through a pull request. Commits follow `scope: summary` in the imperative.

## Localization

UI strings live in `lib/l10n/app_en.arb` and `lib/l10n/app_zh.arb` and are
read through `context.l10n` (`lib/src/locale.dart`). `generate: true` in
`pubspec.yaml` regenerates `lib/l10n/generated/` on pub get, build, and
test; the generated files are committed. Never hardcode user-visible text,
including accessible labels, values, and hints.

## Widget test contract

Strip and module widget tests follow one contract, implemented by
`test/support/strip_harness.dart`:

- **Seed states through constructors.** Tests build blocs with their
  `initial:` state; they never drive them with events to reach a state.
- **Providers own bloc lifecycle.** Always `BlocProvider(create:)`, never
  `.value`. Provider disposal closes blocs unawaited; a test that needs to
  assert disposal subclasses the bloc, records `close()` in a flag, and
  asserts the flag — awaiting `close()` deadlocks.
- **Never await `pumpEventQueue` under FakeAsync.** Pump explicit durations
  instead; the real event loop never runs in a widget test.
- **Pump the production nesting.** `pumpBarHarness` builds config providers
  above a `ModuleScope` above the real strip, so gating tests see exactly
  the providers production sees. Its builder hooks swap one bloc without
  changing the tree's shape.
- **Start no samplers.** Seeded builders stand in for the production
  `Started` path; anything that opens sockets, timers, or D-Bus names stays
  in unit tests.

## Project rules

The full constitution lives in [AGENTS.md](https://github.com/dazemc/trickster/blob/main/AGENTS.md). The short version:

- Resemble Denial at every seam that does not require compositor ownership.
- Port compositor-agnostic Denial Dart instead of rewriting it; keep type names at module boundaries.
- No features Denial's bar lacks until parity is real.
- Never stop the user's graphical session on their behalf; kill only the Trickster process when testing.
- Run `gh` and networked Git outside any sandbox.

## Packaging

Planned, not published:

- Source `trickster` PKGBUILD plus a `-bin` AUR path mirroring Denial's split packaging.
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

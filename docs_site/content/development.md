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

## Documentation site

`docs_site/` is a separate Jaspr project with its own `pubspec.yaml`, so the root `flutter pub get` does not fetch its dependencies and a fresh clone reports analyzer errors from `docs_site/**` until they are fetched once:

```sh
dart pub global activate jaspr_cli 0.24.0-beta.2
cd docs_site
dart pub get --enforce-lockfile   # fresh clone, before flutter analyze
dart analyze
jaspr build                       # output in build/jaspr/
tool/prepare_pages.sh             # rewrite URLs for the /trickster/ Pages path
```

The docs workflow pins Dart 3.14.1 and the same Jaspr CLI. `jaspr build`
generates `lib/main.client.options.dart` and `lib/main.server.options.dart`;
commit the changes it makes and never hand-edit those files. `jaspr serve`
runs the development server on port 8080.

Code lands on the single `working` branch; every markdown file commits directly on `main` in its own commit and is merged back into `working`. Each step is committed separately as it lands proven and is removed from `.llm/todo.md`, and a finished phase merges back into `main` through a pull request. Commits follow `scope: summary` in the imperative.

## Localization

UI strings live in `lib/l10n/app_en.arb` and `lib/l10n/app_zh.arb` and are
read through `context.l10n` (`lib/src/locale.dart`). `generate: true` in
`pubspec.yaml` regenerates `lib/l10n/generated/` on pub get, build, and
test; the generated files are committed. Never hardcode user-visible text,
including accessible labels, values, and hints.

## Releases

Pushing a `v*` tag runs `.github/workflows/release.yml`:

1. The tag is checked against `pubspec.yaml`, then `dart analyze lib bin test`
   and `flutter test` run.
2. The Linux release bundle is built (including the AOT `tricksterctl`) and
   handed to an Arch container, where the source `PKGBUILD` packages it via
   `TRICKSTER_PREBUILT_BUNDLE` and the AUR recipe's `pkgver` and `sha256sums`
   are refreshed from the built artifact. The package's `asset.sha256` is
   produced in the same job.
3. The package and `asset.sha256` are attached to the GitHub release, the
   refreshed pin is committed to the default branch, and only then is the
   recipe pushed to aur.archlinux.org's `master` with the `AUR_SSH_KEY`
   deploy key.

A `workflow_dispatch` run defaults to `dry_run: true`: it builds and uploads
the bundle, package, and pin artifacts without releasing, pinning, or
publishing. Clearing `dry_run` on a tag dispatch runs the full release path.

Locally, the same package can be produced with

```sh
makepkg --nodeps --nocheck   # in packaging/arch, after a release build
makepkg -f                   # in packaging/aur/trickster-bin, from the asset
```

### Publishing to the AUR by hand

The `aur` job covers releases; provision `AUR_SSH_KEY` (an SSH private key
registered with the AUR account) in the repository secrets. Without it, or
for a one-off, push the refreshed recipe by hand:

```sh
git clone ssh://aur@aur.archlinux.org/trickster-bin.git
cd trickster-bin
cp <checkout>/packaging/aur/trickster-bin/{PKGBUILD,.SRCINFO} .
git add PKGBUILD .SRCINFO
git commit -m "Update to <version>"
git push origin HEAD:master
```

The default branch there is `master`, not `main` — a push to `main` is
rejected by the AUR hooks. The recipe's `pkgver` and `sha256sums` come from
the pin commit and must match the release asset; verify with a fresh clone
before calling it done.

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
- **One harness pump per test.** `pumpBarHarness` reuses the providers it
  already built, so pumping it twice silently ignores the second call's
  `settings:`; split the test instead.

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
| No GPU pill, stderr names an NVML failure | Driver/library version mismatch after an update; reload the NVIDIA kernel modules or reboot |

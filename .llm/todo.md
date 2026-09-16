# Trickster TODO

The work list, in build order. `AGENTS.md` is the constitution; this file is
the queue. Remove items as they land — do not check them off, do not let it
rot.

Authorized work only: the queue grants exactly the steps it lists, top-down,
and never overrides the constitution, `.llm/workflow.md`, or the domain notes
(see `AGENTS.md` → Instruction precedence).

Every step is one action with its own done-criteria. Work top-down, one step
at a time: implement it, prove it with `flutter analyze` + `flutter test`
(plus a release build when native code changes), then remove it. Never remove
an untested step; never batch multiple steps into one change.

Sizes: S <1 day, M 1–3 days, L 3+ days.

## Phase 18 — bar options and layout

The user's review of the live bar: pills overlap when a cluster outgrows
its space; meters and clock need more options; media needs display modes;
and the modules page needs visible drop targets and honest unavailable
rows.

- **18.7 (S) Unavailable modules refuse enablement.** The settings page
  cannot enable a module whose probe failed, and the row carries the
  reason; a configured module that fails its probe is surfaced as
  unavailable instead of silently dead. Done when tests cover the refused
  toggle and the reason text.
- **18.8 (M) Screencopy backdrop sampling.** Outputs with no awww/swww
  image (a solid or compositor background) get no sample today. Capture the
  output's strip band with `grim` and run it through the existing candidate
  extractor, cached and sampled only on start/display change. Done when a
  display with no cache file still reports candidates on the live bar and
  settings page, and grim's absence degrades silently.

## Phase 19 — settings frame performance

The settings window stutters below 60 fps on the 4K@60 output (scale 2).
Ours: every controller notification rebuilds the shell and the active page,
and drags preview on every pointer event. Not ours: the Linux GTK embedder
provides no vsync callback, so the engine paces on a fixed 60 Hz fallback
that is not phase-locked to the compositor. Upstream
`flutter/flutter#191245` tracks compositor-driven pacing with the Wayland
subsurface renderer from `#191389`. The decision is to wait for that work
to reach a stable release — do not fork, patch, or pin a patched engine
while other packages share the stock SDK.

- **19.1 (S) Measure the settings frame budget.** A profile build of
  settings mode records build/raster/vsyncOverhead per frame plus the
  number of rebuilds and pointer events during a slider drag. Done when the
  numbers say whether the app's build work or the engine cadence dominates.
- **19.2 (M) Scope and coalesce settings rebuilds.** Drag previews collapse
  to one per frame, and a controller change rebuilds only the widgets that
  read it (section-scoped listenables; the shell keeps to locale and
  load/error). Done when a drag's build times fit the frame budget and the
  settings tests stay green.

## Phase 21 — service diagnostics

- **21.1 (S) Log an unavailable NVIDIA stack once.** When the NVIDIA driver
  is present (`/proc/driver/nvidia/version`) but NVML returns no devices, log
  one line naming the failure (for example the driver/library version
  mismatch) instead of the silent empty reading; keep the best-effort
  behavior. Done when a forced NVML failure produces exactly one stderr line
  and sampling still runs.

## Phase 22 — settings fixes and bar interactions

- **22.1 (S) Displays shows the real output mode.** The settings page's
  output list reports a size that does not match the monitor's mode (a
  scaled 4K display reads 1920x1080 at scale 2). Report the mode the
  compositor drives, or label the logical size honestly, from the native
  outputs enumeration. Done when the live page matches the compositor's mode
  for every connected output and a test pins the mapping.
- **22.2 (M) Clock calendar popup.** Clicking the clock pill opens a month
  calendar on a transient overlay surface (same lifecycle as the tray menu:
  opens toward the output's interior, closes on outside click and Escape,
  honors the accent). Done when the live bar opens the calendar from the
  clock and widget tests pin the grid, keys, and dismissal.

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

## Phase 17 — workspace pip styles

The rail draws numbers today. The user wants a style choice: dots, numbers,
Roman numerals, an SVG from a link, or a local image browsed from the
settings application. One chosen asset applies to every pip unless the user
asks for per-workspace mapping. Every style keeps the active lens,
occupied/empty tinting, and the accessibility labels.

- **17.2 (M) Dots and Roman numerals.** The rail paints the configured
  glyph for every pip, keeping the lens, tints, and labels. Done when the
  live bar shows each style and widget tests pin the glyphs and tints.
- **17.3 (M) SVG link pips.** An SVG fetched from the configured link
  renders as pip artwork, decoded off the frame loop and cached at display
  size with eviction, falling back to numbers when a load fails. Done when
  the live rail paints a linked SVG.
- **17.4 (M) Local image pips.** A browsed local image renders as pip
  artwork through the same decode/cache path, with the settings application
  offering a file browse control. Done when the live rail paints a browsed
  image.

## Phase 18 — bar options and layout

The user's review of the live bar: pills overlap when a cluster outgrows
its space; meters and clock need more options; media needs display modes;
and the modules page needs visible drop targets and honest unavailable
rows.

- **18.1 (M) Pills resize to avoid overlap.** The strip's three zones share
  one row but paint as a free stack, so a long leading/trailing cluster
  overlaps the centered rail. Clamp each zone to its available span so
  pills shrink or ellipsize instead of colliding. Done when a long-content
  bar shows no overlap on the live strips and a widget test pins the
  clamped widths.
- **18.2 (M) Meter caption parity and custom prefixes.** CPU and GPU both
  expose the caption source choice, and the source gains a custom prefix
  typed in the settings UI. Done when both panels offer generic/device/
  custom, the typed prefix round-trips, and the live pills show it.
- **18.3 (M) Meter thresholds and colors.** GPU gains warn/critical
  thresholds like CPU, and both meters' threshold tint colors become
  configurable in the document and the settings UI. Done when the colors
  round-trip and the live pills tint with them.
- **18.4 (M) Clock depth.** Add the clock options the user settles at
  planning time (candidates: `clock.show_seconds`, a custom time pattern,
  date caption style). Done when each option renders on the bar, resets,
  and has config plus widget tests.
- **18.5 (M) Media display modes.** `media.mode` picks full, semi-full, or
  compact; tapping the pill still cycles temporarily and the configured
  mode returns on relaunch. Done when the modes render, the tap cycle is
  transient, and a relaunch restores the setting.
- **18.6 (S) Complete the module drop targets.** "Drop a module here"
  shows on empty zones and an empty Disabled section; the Disabled section
  accepts drops to turn a module off; a disabled row can be dragged back
  into a zone; and releasing below a zone's last row appends there. Done
  when widget tests drop below the last trailing row, drag a module to
  Disabled, and drag one back out.
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

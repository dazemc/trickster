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

## Phase 14 — settings depth

The settings window covers the bar's documents but not every knob, and is an
opaque window while the bar is glass. This phase fills the surface out.

- **14.12 (M) Appearance per display.** The appearance keys resolve per
  output: the accent source and wallpaper pick become per-display values,
  falling back to the global appearance keys, and the settings UI edits
  each display's own. Done when two outputs can hold different picks and
  the live bars show their own accents.
- **14.13 (S) Hide the clock date caption.** Add `clock.show_date` (hide the
  date caption) with the settings toggle; the bar honors it live. Done when
  it renders on the bar, resets, and has config plus widget tests.
- **14.14 (S) Force the opaque bar fill.** Add `appearance.blur` (force the
  opaque fill even when the host can blur) with the settings toggle; the bar
  honors it live. Done when it renders on the bar, resets, and has config
  plus widget tests.
- **14.15 (S) Hide the meter sparkline.** Add `meter.sparkline` (hide CPU/GPU
  history) with the settings toggle; the bar honors it live. Done when it
  renders on the bar, resets, and has config plus widget tests.
- **14.16 (M) Settings window transparency.** Make the settings toplevel
  translucent (GTK RGBA visual plus translucent Flutter surfaces) so the
  host blurs behind it, with an opaque fallback when the compositor cannot.
  Done when the live window shows the blurred desktop on Hyprland and the
  fallback stays legible.

## Phase 16 — workspace chain

Denial's rail is a fixed `1..count` on every display. The user wants a main
display whose workspaces start at 1, each subsequent display appending its
own block (main 4 → 1-4, next 3 → 5-7), with the display order
user-configurable. This is bar numbering and click targets only; workspace
ownership stays with the compositor.

- **16.3 (M) Chain order controls.** The workspaces gear panel lists the
  connected displays in chain order with drag handles and a Main badge on
  the first row, each showing its resulting range; a set-as-main action
  moves a display to the front, writing `display_order`. Done when
  reordering or marking writes the document and the live bars re-range.

## Phase 17 — workspace pip styles

The rail draws numbers today. The user wants a style choice: dots, numbers,
Roman numerals, an SVG from a link, or a local image browsed from the
settings application. One chosen asset applies to every pip unless the user
asks for per-workspace mapping. Every style keeps the active lens,
occupied/empty tinting, and the accessibility labels.

- **17.1 (S) Pip style option.** Add `workspaces.pip_style` (`number`
  default, `dot`, `roman`, `svg`, `image`) and the svg/image source keys to
  the settings document. Done when the document round-trips every style and
  decode rejects unknown values.
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
- **18.6 (S) Always-visible drop targets.** Every module zone keeps a
  "Drop a module here" target even when populated, and the Disabled area
  accepts drops so a module can be dragged there to turn off. Done when a
  widget test drags a module to Disabled and the targets stay visible.
- **18.7 (S) Unavailable modules refuse enablement.** The settings page
  cannot enable a module whose probe failed, and the row carries the
  reason; a configured module that fails its probe is surfaced as
  unavailable instead of silently dead. Done when tests cover the refused
  toggle and the reason text.

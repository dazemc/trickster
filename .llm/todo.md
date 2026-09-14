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

- **14.12 (M) Wallpaper accent per display.** Monitors can run different
  wallpapers, so the wallpaper-accent pick becomes per-output too: the
  settings UI lists each display's candidates and each strip resolves its
  own output's pick. Done when two outputs can hold different picks and
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

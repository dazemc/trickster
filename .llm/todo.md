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

- **14.11 (M) Workspaces configured per display.** The workspace count
  becomes per-output (each monitor may want a different rail length) in the
  settings document and the settings UI; the strip honors each output's
  count, and the panel carries no redundant global slider (`workspace_count`
  stays the document fallback). Done when the document round-trips per-output
  counts, the live multi-monitor bars show different rail lengths, and the
  settings UI shows only per-display controls.
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

- **16.1 (M) Display order and range model.** Add `workspaces.display_order`
  (ordered connectors, first is the main display) to the settings document
  and compute each connected display's range as the cumulative per-display
  counts: listed connectors first in list order, unlisted connected displays
  appended in host order. Done when the document round-trips the order and
  unit tests pin the range math (empty order, custom order, unlisted append,
  disconnected main).
- **16.2 (M) Rail shows its assigned range.** The strip renders its output's
  absolute range (main 4 → 1-4, next 3 → 5-7) in place of the fixed
  `1..count`; pip presses keep targeting the printed number. Done when the
  live bars show different absolute ranges and widget tests cover the
  mapping.
- **16.3 (M) Chain order controls.** The workspaces gear panel lists the
  connected displays in chain order with drag handles and a Main badge on
  the first row, each showing its resulting range; a set-as-main action
  moves a display to the front, writing `display_order`. Done when
  reordering or marking writes the document and the live bars re-range.

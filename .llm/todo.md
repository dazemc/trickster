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

## Phase 24 — sink volume

The media pill shows no volume today: the host's own keys and mixers are the
only way to change the default sink. Show the level and let the pill set it.

- **24.5 (M) Volume slider on click.** Clicking the readout opens a slider
  on a transient overlay surface (the calendar/tray-menu lifecycle: anchored
  and clamped, outside-click and Escape dismissal, hosted-blur choice
  honored), and dragging sets the sink volume live. Done when the live
  slider moves the sink and widget tests pin the drag mapping and dismissal.

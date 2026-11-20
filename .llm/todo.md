# Trickster TODO

The work list, in build order. `AGENTS.md` is the constitution; this file is
the queue. Remove items as they land — do not check them off, do not let it
rot.

Authorized work only: the queue grants exactly the steps it lists, top-down,
and never overrides the constitution, `.llm/workflow.md`, or the domain notes
(see `AGENTS.md` → Instruction precedence).

Every step is one action with its own done-criterion. Work top-down, one step
at a time: implement it, prove it with `flutter analyze` + `flutter test`
(plus a release build when native code changes), then remove it. Never remove
an untested step; never batch multiple steps into one change.

The `.llm/` reinitialization does **not** authorize performance, refresh,
memory, or lifecycle work. Findings in `.llm/suggestions.md` remain proposals
until the user escalates them here.

Sizes: S <1 day, M 1–3 days, L 3+ days.

## Authorized step

- S: Track overlay monitors natively. Assign `surface->monitor` in
  `trickster_overlay_surface_new`, refuse an untrackable null-monitor overlay
  and return null to the menu/tooltip open callers, destroy matching menu and
  tooltip windows from `monitor_removed_cb` through a shared helper, and
  destroy each overlay blur effect before its window. Done when native
  source-contract tests pin the assignment, null refusal, helper references to
  both arrays, and removal call; analyze/full tests and a release build are
  green. Defer live output removal because the screen is off.

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

- M: Coordinate transient overlays through one app-owned
  `OverlayCoordinator` service (not a bloc). Tray menu, calendar, and volume
  slider are modal; tooltips are non-modal. At most one modal is open. A
  modal request dismisses the active modal and any tooltip (tooltips first);
  a tooltip request is refused while a modal is open. Same-kind requests
  retarget or replace without dismissing other kinds. Inject the coordinator
  into the four overlay blocs, register generation-safe async dismissal
  callbacks, and release claims on failed open, dismiss, close, and
  retained-view clearing. Bound each dismissal with a short timeout so a dead
  surface cannot hang the next open; keep the existing `close()` overrides
  and generation guards, and add no native policy or timers. Done when tests
  prove menu then calendar dismisses menu first, tooltip behind a menu is
  refused, tooltip then menu closes the tooltip, same-kind retarget, release
  on close/retained view, and timeout recovery; analyze and full tests are
  green.

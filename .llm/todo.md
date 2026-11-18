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

## Phase: currency, dependency majors, and shell capabilities

- S: Honor `ext-background-effect` capabilities. Done when the native manager
  listener folds the blur capability bit into the probe, the check UI, settings
  toggle, and blur regions fall back when blur is unavailable, and a release
  build is exercised on a host that advertises the manager.

- S: Coalesce Hyprland workspace refresh events. Done when incoming events are
  debounced, in-flight refreshes are coalesced, emissions are deduped, and a
  live workspace switch updates the pill once.

- S: Key overlay entries by view. Done when overlay builders select only the
  calling view's session, so a hovered tooltip on one output does not rebuild
  strips on other outputs.
